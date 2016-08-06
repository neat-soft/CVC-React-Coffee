# CVC UI

# Pre-requisites
  * NodeJS 4.4.5
  * Global NPM:
    * CoffeScript 1.9.3
    * supervisor


To start development environment make sure you have config/private/app.coffee
```
module.exports =
  nodeEnv: 'development'

  socialApiFactory:
    baseUrl: 'https://dev.familymediapartners.com:6005'
    auth:
      username: 'dev'
      password: 'dsflkjj234'
    retry: 0
```


1. run `npm install` make sure it succeeds before moving on
1. run `grunt dev` to start process of autobuilding assets
1. in a separate terminal run `npm run dev` to bring up the development server
1. browse localhost:6007


you can sign in with `test@curvesconnect.com` password: `test`

