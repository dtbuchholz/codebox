# Webhook receiver - multi-stage build
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o webhook-receiver .

# Final image
FROM alpine:latest

RUN apk --no-cache add ca-certificates tmux

COPY --from=builder /app/webhook-receiver /usr/local/bin/

EXPOSE 8080

CMD ["webhook-receiver"]
