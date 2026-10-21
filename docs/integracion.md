# Integracion y exportacion de cartera

El analizador `src/operations/portfolio.py` acepta un archivo JSON local y
es de solo lectura. No conecta a una red, no consulta precios y no envia
transacciones. La fuente de datos debe conservar bloque, red, direccion del
contrato y decimales fuera de este esquema si se distribuye una exportacion
operativa.

## Contrato JSON

```json
{
  "as_of": 1760000000,
  "cash": 650000,
  "lender_principal": 600000,
  "reserve": 20000,
  "sector_stress_bps": {"trade": 600, "services": 400},
  "lines": [
    {
      "line_id": 1,
      "sector": "trade",
      "status": "active",
      "limit": 200000,
      "principal": 100000,
      "interest": 1200,
      "collateral": 40000,
      "apr_bps": 1200,
      "next_due": 1759000000
    }
  ]
}
```

Los importes de este ejemplo estan abreviados para lectura. Una exportacion
de un token de 18 decimales debe suministrar enteros en unidades base, sin
comas ni notacion flotante. `as_of` y `next_due` son segundos Unix.

Estados admitidos: `open`, `active`, `delinquent`, `defaulted`,
`liquidated`, `closed`. El programa valida IDs unicos, principales dentro
del limite, tasas dentro de 0-10.000 bps, ausencia de deuda en lineas
terminales y respaldo del colateral y la reserva por el efectivo informado.

## Ejecucion

```bash
python src/operations/portfolio.py examples/portfolio.json
python -m pytest -q tests/test_portfolio_snapshot.py
```

La salida JSON incluye totales, ratios enteros en bps y una lista ordenada
de sectores. Una integracion debe tratar la salida como informacion
observacional: las cifras no sustituyen las lecturas de `CreditCore` para
autorizar operaciones de estado.

## Reconciliacion

1. Fijar un unico bloque de lectura para todos los contratos.
2. Leer saldo del token, capital lender, reservas y lineas del mismo bloque.
3. Convertir todos los importes a unidades base antes de serializar.
4. Comparar principal agregado con los contadores de `CreditCore`.
5. Guardar hash del JSON exportado y bloque de origen junto al informe.

Si falla una validacion, no sustituir importes negativos por cero. Corregir
la exportacion o escalar la discrepancia a operaciones.
