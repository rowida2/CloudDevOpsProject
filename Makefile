# Tiny shortcut layer so we never have to remember long commands.
# Usage: make up / make down / make logs / make reset

.PHONY: help up down logs ps rebuild clean reset health

help:
	@echo "make up       - build & start the whole stack"
	@echo "make down     - stop the stack (keeps the database volume)"
	@echo "make logs     - follow logs of every service"
	@echo "make ps       - show container status + health"
	@echo "make rebuild  - rebuild images from scratch and start"
	@echo "make reset    - stop the stack AND delete the database volume"
	@echo "make health   - call each service health endpoint"

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

rebuild:
	docker compose build --no-cache
	docker compose up -d

clean:
	docker compose down -v

reset: clean
	docker compose up -d --build

health:
	@echo "--- frontend ---";  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/ || true
	@echo "--- auth ---";      docker compose exec -T auth-service python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:5000/health').read().decode())" || true
	@echo "--- roadmap ---";   docker compose exec -T roadmap-service wget -qO- http://127.0.0.1:8080/api/roadmap || true
