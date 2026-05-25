FROM node:22-alpine

WORKDIR /app

COPY package.json ./
COPY server.js ./
COPY knowledge.md ./
COPY common-english-words.txt ./
COPY evals ./evals
COPY scripts ./scripts
COPY training ./training

ENV NODE_ENV=production
ENV POKONTACT_HOST=0.0.0.0
ENV POKONTACT_PORT=8787

EXPOSE 8787

CMD ["node", "server.js"]
