module.exports =
  server:
    host          : '0.0.0.0'
    port          : if process.env.PORT? then process.env.PORT.split(',') else [6007,6008]
    maxQueueSize  : 200
    forwardHmacKey: 'TEST'

  newrelic:
    appName: 'CurvesConnect UI'

  captchaClient:
    baseUrl: 'http://internal-captcha-elb-bumbvc785tb9-1589373926.us-east-1.elb.amazonaws.com'

  siteDefinitions:
    portMap:
      '6007': 'curvesconnect'
      '6008': 'conectandocurvas'

  zendeskApi:
    remoteUri: 'https://curvesconnect.zendesk.com/api/v2'


module.exports =
  nodeEnv: 'development'

  socialApiFactory:
    baseUrl: 'https://dev.familymediapartners.com:6005'
    auth:
      username: 'dev'
      password: 'dsflkjj234'
    retry: 0