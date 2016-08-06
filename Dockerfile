FROM docker-reg:5001/nodejs:latest

RUN \
  yum install -y sox && \
  adduser app -d /home/app && \
  chown -R app:app /home/app
ENV HOME /home/app

ADD package.json /app/package.json
COPY local_modules /app/local_modules
RUN chown -R app:app /app

USER app
WORKDIR /app
RUN \
  mkdir -p src/main && npm install
USER root

EXPOSE 6007
EXPOSE 6008
CMD forever --spinSleepTime 2000 lib/server/cvc_server.js

ADD deploy.tar.gz /app
RUN chown -R app:app /app
USER app
RUN coffee -o lib --compile src