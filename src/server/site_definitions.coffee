_ = require('lodash')

exports.SiteDefinitions = ($options) ->
  return self = _.merge {
    curvesconnect:
      siteName: 'curvesconnect.com'
      siteUrl: 'curvesconnect.com'
      socialApiDatabase: ''
      supportedLanguages: ['en']
      googleAnalyticsId: 'UA-65762201-1'
      googleSiteVerification: 'rwOc4pafjMJ3IDvevow3kGzLl-iWIiSYUzC48hGzJzA'
      messageOverrides:
        common:
          siteTitle: 'CurvesConnect.com'
    conectandocurvas:
      siteName: 'conectandocurvas.com'
      siteUrl: 'conectandocurvas.com'
      supportedLanguages: ['sp']
      googleAnalyticsId: 'UA-65762201-2'
      googleSiteVerification: 'cwBu14JsTbkxM_vUEPZoPNLKVfWcPiqmZ2AfFyyqVqY'
      messageOverrides:
        common:
          siteTitle: 'ConectandoCurvas.com'
  }, $options

exports.LocalizedMessages = ($p, $u, siteDefinitions) ->
  languages =
    en: require('../locale/en')
    sp: require('../locale/sp')

  defaultLanguage = languages.en
  localizedCache = {}
  return self = {
    getMessageBundle: (siteKey, language, bundleName) ->
      messages = self.getMessages(siteKey, language)
      messages = languages?[language][bundleName]

    getMessageBundles: (siteKey, language, bundleNames...) ->
      unless languages[language]?
        bundleNames.shift(language)
        language = null
      bundles = {}
      _.each bundleNames, (bundleName) ->
        bundles[bundleName] = self.getMessageBundle(siteKey, language, bundleName)
      bundles

    getMessages: (siteKey, language) ->
      language ?= siteDefinitions[siteKey].supportedLanguages[0]
      cacheKey = "#{siteKey}-#{language}"
      return localizedCache[cacheKey] if localizedCache[cacheKey]?
      siteBundle = siteDefinitions[siteKey]?.messageOverrides || {}
      messages = languages?[language] || {}
      localizedCache[cacheKey] = _.merge {}, defaultLanguage, messages, siteBundle
  }

