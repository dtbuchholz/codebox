.PHONY: build deploy logs ssh status clean help

APP_NAME ?= agent-box
REGION ?= sjc

help:
	@echo "Agent Box - Makefile targets"
	@echo ""
	@echo "  make build      Build Docker image locally"
	@echo "  make deploy     Deploy to Fly.io"
	@echo "  make logs       View Fly.io logs"
	@echo "  make ssh        SSH into the machine"
	@echo "  make status     Check machine status"
	@echo "  make console    Open Fly console"
	@echo "  make clean      Remove local build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  APP_NAME=$(APP_NAME)"
	@echo "  REGION=$(REGION)"

build:
	docker build -t $(APP_NAME):local .

deploy:
	./deploy.sh

logs:
	fly logs -a $(APP_NAME)

ssh:
	@echo "Getting Tailscale IP..."
	@IP=$$(fly ssh console -a $(APP_NAME) -C 'tailscale ip -4' 2>/dev/null | tr -d '\r\n'); \
	if [ -n "$$IP" ]; then \
		echo "Connecting to $$IP:2222..."; \
		ssh -p 2222 agent@$$IP; \
	else \
		echo "Could not get Tailscale IP. Try: fly ssh console -a $(APP_NAME)"; \
	fi

status:
	fly status -a $(APP_NAME)

console:
	fly ssh console -a $(APP_NAME)

# Local development
dev-build:
	docker build -t $(APP_NAME):dev .

dev-run:
	docker run -it --rm \
		-p 2222:2222 \
		-p 8080:8080 \
		-v $$(pwd)/data:/data \
		-e AUTHORIZED_KEYS="$$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)" \
		$(APP_NAME):dev

clean:
	rm -f webhook/webhook-receiver
	docker rmi $(APP_NAME):local $(APP_NAME):dev 2>/dev/null || true
