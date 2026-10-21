# Contribuir

Los cambios de contratos deben incluir una descripcion de la transicion de
estado, las unidades de cada parametro y tests con el token local. Los cambios
del analizador deben conservar aritmetica entera y salida determinista.

Antes de abrir un PR:

```bash
python scripts/compile.py
python -m pytest -q
python scripts/check_loc.py
```

Documente los cambios de interfaz publica en `docs/` y registre cambios
compatibles de version en `CHANGELOG.md`. Los parametros de produccion y las
direcciones de despliegue no pertenecen a este repositorio.
