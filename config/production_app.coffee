module.exports =
  server:
    forceHttps: false
  loggerFactory:
    papertrail:
      host: 'logs2.papertrailapp.com'
      port: 30821
      appName: 'cvc_ui'

  socialApiFactory:
    baseUrl: 'http://internal-social-api-1970977098.us-east-1.elb.amazonaws.com:80'
    retry: 0

  siteDefinitions:
    curvesconnect:
      socialApiDatabase: 'cvc_en'
    conectandocurvas:
      socialApiDatabase: 'cvc_sp'
