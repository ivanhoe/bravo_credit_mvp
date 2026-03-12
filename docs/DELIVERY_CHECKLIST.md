# BravoCredit - Delivery Checklist

> Checklist final para preparar la entrega del reto tecnico como repositorio publico.
> La entrega no es un documento aparte: la entrega es el repo.

---

## 1. Objetivo de la entrega

Antes de compartir el repositorio, este debe permitir que una persona externa:

- entienda rapido que problema resuelve
- levante el proyecto sin adivinar pasos
- ejecute tests
- pruebe el flujo principal
- vea claramente que esta implementado y que queda fuera

---

## 2. Entregables minimos

- [ ] repositorio publico con toda la solucion
- [ ] codigo fuente funcional
- [ ] historial de commits legible y progresivo
- [ ] `README.md` actualizado y operativo
- [ ] `docs/ARCHITECTURE_V2.md` alineado con la implementacion real
- [ ] `docs/IMPLEMENTATION_PLAN.md` consistente con el alcance final
- [ ] `.env.example` completo y correcto
- [ ] `Justfile` o comandos equivalentes funcionando
- [ ] `docker-compose.yml` para Postgres local
- [ ] tests automatizados reales

---

## 3. README final

El `README.md` debe cubrir, como minimo:

- [ ] resumen corto del problema y la solucion
- [ ] stack tecnico
- [ ] decisiones de arquitectura principales
- [ ] instrucciones de setup local
- [ ] instrucciones para cargar variables de entorno
- [ ] instrucciones para crear y migrar base de datos
- [ ] instrucciones para correr la app
- [ ] instrucciones para correr tests
- [ ] endpoints principales o coleccion de ejemplo
- [ ] descripcion del flujo async y del requisito `3.7`
- [ ] alcance implementado vs alcance diferido
- [ ] tradeoffs y siguientes pasos

---

## 4. Higiene del repositorio

- [ ] no existe `.env` en el repo
- [ ] no hay secrets reales en codigo, commits o docs
- [ ] el PDF del reto NO esta incluido en el repo publico
- [ ] no hay archivos basura (`.DS_Store`, logs, builds locales, caches)
- [ ] `.gitignore` cubre archivos locales y editor state
- [ ] la rama principal esta limpia antes de publicar

---

## 5. Configuracion y secretos

- [ ] `SECRET_KEY_BASE` viene de env
- [ ] `GUARDIAN_SECRET_KEY` viene de env
- [ ] `CLOAK_KEY` viene de env
- [ ] `DATABASE_URL` viene de env
- [ ] `TEST_DATABASE_URL` viene de env o esta documentado su uso
- [ ] `.env.example` usa placeholders, no valores reales
- [ ] el proyecto falla rapido si faltan variables criticas

---

## 6. Reproducibilidad local

- [ ] `mix deps.get` funciona
- [ ] `mix ecto.create` funciona
- [ ] `mix ecto.migrate` funciona
- [ ] `mix phx.server` levanta correctamente
- [ ] `mix test` corre en local
- [ ] `mix credo --strict` pasa
- [ ] `mix format --check-formatted` pasa
- [ ] el setup local esta descrito con comandos exactos

---

## 7. Funcionalidad minima demostrable

- [ ] `POST /api/applications` crea una solicitud
- [ ] se persiste `application`
- [ ] se persiste `application_event`
- [ ] se encola trabajo async critico
- [ ] existe al menos un flujo DB-triggered para `3.7`
- [ ] `GET /api/applications/:id` devuelve detalle correcto
- [ ] `GET /api/applications` permite listar y filtrar
- [ ] `PATCH /api/applications/:id/state` valida transiciones
- [ ] el provider mock por pais funciona
- [ ] el job de riesgo funciona
- [ ] LiveView refleja cambios relevantes

---

## 8. Calidad tecnica

- [ ] los modulos tienen responsabilidades claras
- [ ] el contrato de `Pipeline.Context` es consistente
- [ ] YAML de paises esta validado al arranque
- [ ] no hay contradicciones entre arquitectura y codigo
- [ ] las reglas por pais no dependen de hardcodes innecesarios
- [ ] el flujo sync y async esta claramente separado
- [ ] los eventos de dominio tienen payloads consistentes
- [ ] la autorizacion por recurso no depende de params del cliente

---

## 9. Tests esperados

- [ ] tests de contexto o dominio
- [ ] tests de pipeline
- [ ] tests de workers
- [ ] tests de API / controllers
- [ ] tests de state machine
- [ ] tests de parsing o carga de YAML
- [ ] tests de autorizacion basica

No hace falta cobertura total, pero si evidencia de criterio y pruebas en los puntos de riesgo.

---

## 10. Demo final

Antes de compartir el repo, poder ejecutar esta secuencia:

1. copiar `.env.example` a `.env`
2. cargar variables de entorno
3. levantar Postgres local
4. correr `mix deps.get`
5. correr `mix ecto.setup`
6. correr `mix test`
7. correr `mix phx.server`
8. crear una solicitud
9. observar procesamiento async
10. consultar estado final

---

## 11. Mensaje de entrega

Al enviar el repositorio, conviene acompanar con un mensaje corto que diga:

- que el repo contiene la solucion completa
- como correrlo localmente
- donde esta la arquitectura
- cuales fueron los tradeoffs principales

---

## 12. Corte recomendado para esta prueba

Si falta tiempo, priorizar en este orden:

1. flujo vertical funcional
2. tests del flujo principal
3. README impecable
4. setup reproducible con Docker para Postgres
5. docs de arquitectura alineadas al codigo

No sacrificar consistencia por agregar features opcionales.
