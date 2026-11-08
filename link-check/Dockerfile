FROM node:22-alpine
LABEL org.opencontainers.image.source=https://github.com/robertblust/id-blust-ch
WORKDIR /app
COPY package.json server.mjs ./
COPY lib/ lib/
USER node
CMD ["node", "server.mjs"]
