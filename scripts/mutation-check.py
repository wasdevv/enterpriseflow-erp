#!/usr/bin/env python3
"""Sabota uma copia do codigo, uma regra por vez, e confere que algum teste quebra.

Teste verde so vale se ele falha quando o codigo esta errado. Cada entrada remove um bloqueio,
uma ordenacao ou uma verificacao de idempotencia. "NAO DETECTADA" significa teste fraco.
Uso: mutation-check.py [trecho-do-nome,...]
"""
import os, re, shutil, subprocess, sys, tempfile
SRC=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK=tempfile.mkdtemp(prefix='ef-mut-')+'/copy'
M=[
 ('sem WITH LOCK no saldo','src/infrastructure/repositories/EF.Infrastructure.Repositories.Stock.pas',"warehouse_id = :warehouse_id WITH LOCK'","warehouse_id = :warehouse_id'",'TStockIntegration'),
 ('sem WITH LOCK no cliente','src/infrastructure/repositories/EF.Infrastructure.Repositories.Support.pas',"FROM customers WHERE id = :id WITH LOCK'","FROM customers WHERE id = :id'",'ConcurrentOrdersCannotExceedCreditLimit'),
 ('sem ordenar itens do pedido','src/application/services/EF.Application.Sales.pas',"  SortOrderItems(Result);\n","",'BalancesAreLockedInAscending'),
 ('transferencia sem ordem de deposito','src/application/services/EF.Application.Inventory.pas',"if AFromWarehouseId < AToWarehouseId then","if True then",'TransfersInOpposite'),
 ('sem SKIP LOCKED','src/infrastructure/repositories/EF.Infrastructure.Repositories.Support.pas',"ORDER BY id WITH LOCK SKIP LOCKED'","ORDER BY id WITH LOCK'",'ClaimSkips'),
 ('sem conferir posse na outbox','src/infrastructure/repositories/EF.Infrastructure.Repositories.Support.pas',"AND (claimed_until IS NULL OR claimed_until < :now_value) ","",'ClaimedEventIsNotTaken'),
 ('sem WITH LOCK na parcela e titulo','src/infrastructure/repositories/EF.Infrastructure.Repositories.Sales.pas',"WHERE id = :id WITH LOCK'","WHERE id = :id'",'TFinanceIntegration'),
 ('retry em POST sem chave','src/infrastructure/integrations/EF.Infrastructure.Http.pas',"Result := SameText(ARequest.Method, 'GET') or (ARequest.IdempotencyKey <> '');","Result := True;",'PostWithoutKey'),
 ('sem cabecalho Idempotency-Key','src/infrastructure/integrations/EF.Infrastructure.Http.pas',"LRequest.Headers[1].Value := AEvent.IdempotencyKey;","LRequest.Headers[1].Value := '';",'TOutboxIntegration'),
 ('log sem redacao','src/infrastructure/integrations/EF.Infrastructure.Http.pas',"LEntry.ResponseExcerpt := RedactSecrets(ABody);","LEntry.ResponseExcerpt := ABody;",'LogsNeverContain'),
 ('reserva ativa nao conferida ao fechar','src/infrastructure/repositories/EF.Infrastructure.Repositories.Stock.pas',"WHERE id = :id AND status = ''ACTIVE''","WHERE id = :id",'ClosingReservationTwice'),
 ('guarda de NULL em dinheiro removida','src/infrastructure/database/EF.Infrastructure.Database.pas',"  if AField.IsNull then\n    raise EDatabaseError.CreateFmt('Valor nulo","  if False then\n    raise EDatabaseError.CreateFmt('Valor nulo",'UnreadableMoney'),
 ('recusa de reserva sem metrica','src/application/services/EF.Application.Sales.pas',"RecordMetric('reservation_refused', E.Message, LStart);\n      LogEvent","LogEvent",'ReservationAboveAvailable'),
 ('dominio nao valida a reserva','src/domain/entities/EF.Domain.Stock.pas',"if AQuantity > Available then\n    raise EInsufficientStock.CreateFmt('Disponível: %s. Solicitado","if False then\n    raise EInsufficientStock.CreateFmt('Disponível: %s. Solicitado",'ThreadsRacing|ReserveRefuses'),
 ('credito sem contar reservados','src/application/services/EF.Application.Sales.pas'," + FUow.Orders.ReservedTotal(ACustomer.Id, AExcludingOrderId)","",'CreditLimitIsEnforced'),
 ('estorno pode repetir','src/application/services/EF.Application.Finance.pas',"if FUow.Receivables.HasReversal(ASettlementId) then","if False then",'ReversalCanHappenOnlyOnce|ConcurrentReversals'),
]
env=dict(os.environ)
env['EF_TEST_DB_PATH']=os.path.expanduser('~/.local/share/enterpriseflow-fb/mut.fdb')
env['EF_TEST_API_PORT']='58766'
res=[]
only=sys.argv[1].split(',') if len(sys.argv)>1 else None
for name,path,old,new,flt in M:
    if only and not any(o in name for o in only): continue
    shutil.rmtree(WORK,ignore_errors=True)
    shutil.copytree(SRC,WORK,ignore=shutil.ignore_patterns('build','.git'))
    p=os.path.join(WORK,path)
    s=open(p,encoding='utf-8').read()
    if old not in s:
        res.append((name,'PADRAO NAO ENCONTRADO','')); print(res[-1],flush=True); continue
    s=s.replace(old,new)
    open(p,'w',encoding='utf-8').write(s)
    # roda cada filtro (separados por |)
    failed=[]; total=0
    for f in flt.split('|'):
        r=subprocess.run([WORK+'/scripts/test.sh','--filter='+f],capture_output=True,text=True,env=env,timeout=400)
        out=r.stdout+r.stderr
        if 'Fatal' in out and 'passaram' not in out:
            failed.append('NAO COMPILOU: '+out[-200:])
        failed+=[l.strip()[:150] for l in out.splitlines() if l.strip().startswith('FAIL')]
    res.append((name,'DETECTADA' if failed else '*** NAO DETECTADA ***',failed[0] if failed else ''))
    print(res[-1],flush=True)

shutil.rmtree(os.path.dirname(WORK),ignore_errors=True)
sys.exit(1 if any(r[1]!='DETECTADA' for r in res) else 0)
