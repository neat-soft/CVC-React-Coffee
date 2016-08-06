jade = require('jade')
mincer = require('mincer')
path = require('path')
url = require('url')
spawn = require('child_process').spawn
_ = require('lodash')
{throttle} = require('core')
inline = require('css-inline')
moment = require('moment')
mailgunFactory = require('mailgun-js')

exports.MailgunApi = ($p, $options) ->
  domains = {}
  self = {
    send: (sendingDomain, msg) ->
      mailgun = domains[sendingDomain] || mailgunFactory(apiKey: $options.apiKey, domain: sendingDomain)
      $p.wrap(mailgun.messages().send msg, $p.ecb())
  }

exports.EmailProviderFactory = ($p, $options, emailRenderer, mailgunApi, localizedMessages, socialApiFactory) ->
  return (siteDefinition) ->
    socialApi = socialApiFactory(siteDefinition.socialApiDatabase)
    getAccountAndProfile = (accountGuid) ->
      [ socialApi.get("/accounts", accountGuid)
        socialApi.get("/profiles/by_account", accountGuid)
        socialApi.get("/accounts", accountGuid, "token")
      ].then (account, profileGuid, loginToken) ->
        socialApi.get("/profiles", profileGuid).then (profile) ->
          $p.resolved(account, profile, loginToken)

    getDefaultVariables = (accountGuid) ->
      getAccountAndProfile(accountGuid).then (account, profile, loginToken) ->
        messages = localizedMessages.getMessages(siteDefinition.siteKey)
        return $p.resolved({
          username: profile.username
          emailAddress: account.emailAddress
          baseUrl: "http://#{siteDefinition.siteUrl || siteDefinition.siteName}"
          cdnPrefix: "http://#{siteDefinition.siteUrl || siteDefinition.siteName}"
          messages: messages
          auth: loginToken
        }, account, profile)

    return self = {
      renderWelcomeEmail: (accountGuid, variables) ->
        getDefaultVariables(accountGuid).then (defaultVariables, account, profile) ->
          variables = _.merge {}, defaultVariables, variables
          emailRenderer.render(siteDefinition.siteKey, "welcome", variables).then (html) -> {
            from: "#{siteDefinition.messageOverrides.common.siteTitle} <info@#{siteDefinition.siteName}>"
            to: $options?.emailOverride || variables.emailAddress
            subject: "Welcome to CurvesConnect.com"
            html: html
            'o:tag': ['welcome']
            'o:campaign': ['welcome']
          }

      renderNewMessageNotification: (senderProfileGuid, receiverAccountGuid, variables) ->
        getDefaultVariables(receiverAccountGuid).then (defaultVariables, account, profile) ->
          socialApi.get("/profiles", senderProfileGuid).then (senderProfile) ->
            variables = _.merge {}, defaultVariables, variables, {sender: senderProfile}
            emailRenderer.render(siteDefinition.siteKey, "message_notification", variables).then (html) -> {
              from: "#{siteDefinition.messageOverrides.common.siteTitle} <info@#{siteDefinition.siteName}>"
              to: $options?.emailOverride || variables.emailAddress
              subject: "New message from #{senderProfile.username}!"
              html: html
              'o:tag': ['new_message']
              'o:campaign': ['new_message']
            }

      renderNewLikeNotification: (senderProfileGuid, receiverAccountGuid, variables) ->
        getDefaultVariables(receiverAccountGuid).then (defaultVariables, account, profile) ->
          socialApi.get("/profiles", senderProfileGuid).then (senderProfile) ->
            variables = _.merge {}, defaultVariables, variables, {sender: senderProfile}
            emailRenderer.render(siteDefinition.siteKey, "like_notification", variables).then (html) -> {
              from: "#{siteDefinition.messageOverrides.common.siteTitle} <info@#{siteDefinition.siteName}>"
              to: $options?.emailOverride || variables.emailAddress
              subject: "Someone on #{siteDefinition.messageOverrides.common.siteTitle} likes you!"
              html: html
              'o:tag': ['new_like']
              'o:campaign': ['new_like']
            }

      renderUnreadMessagesEmail: (accountGuid, variables) ->
        getDefaultVariables(accountGuid).then (defaultVariables, account, profile) ->
          socialApi.get("/messaging/inbox", profile.guid, 0, {pageSize: 0, unreadOnly: true}).then (results) ->
            variables = _.merge {}, defaultVariables, variables || {}, {unreadMessageCount: results.total}
            emailRenderer.render(siteDefinition.siteKey, "unread_messages", variables).then (html) -> $p.resolved {
              from: "#{siteDefinition.messageOverrides.common.siteTitle} <info@#{siteDefinition.siteName}>"
              to: $options?.emailOverride || variables.emailAddress
              subject: "You have unread messages waiting for you!"
              html: html
              'o:tag': ['unread_messages']
              'o:campaign': ['unread_messages']
            }, results.total

      renderDiscoverNewProfiles: (accountGuid, variables) ->
        getDefaultVariables(accountGuid).then (defaultVariables, account, profile) ->
          socialApi.post("/discovery", profile.guid).then (results) ->
            variables = _.merge {}, defaultVariables, variables || {}, {newProfilesToDiscover: results.totalFound}
            emailRenderer.render(siteDefinition.siteKey, "discover_new_profiles", variables).then (html) -> $p.resolved {
              from: "#{siteDefinition.messageOverrides.common.siteTitle} <info@#{siteDefinition.siteName}>"
              to: $options?.emailOverride || variables.emailAddress
              subject: "You have new profiles to discover!"
              html: html
              'o:tag': ['discover_new_profiles']
              'o:campaign': ['discover_new_profiles']
            }, results.totalFound

      renderForgotPasswordNotification: (accountGuid, variables) ->
        getDefaultVariables(accountGuid).then (defaultVariables, account, profile) ->
          variables = _.merge {}, defaultVariables, variables
          emailRenderer.render(siteDefinition.siteKey, "forgot_password", variables).then (html) -> {
            from: "#{siteDefinition.messageOverrides.common.siteTitle} <info@#{siteDefinition.siteName}>"
            to: $options?.emailOverride || variables.emailAddress
            subject: "Forgot you password?"
            html: html
            'o:tag': ['forgot_password']
            'o:campaign': ['forgot_password']
          }

      sendWelcomeEmail: (accountGuid, variables) ->
        self.renderWelcomeEmail(accountGuid, variables).then (renderedMessage) ->
          mailgunApi.send(siteDefinition.siteName, renderedMessage)

      sendNewMessageNotification: (senderProfileGuid, receiverAccountGuid, variables) ->
        self.renderNewMessageNotification(senderProfileGuid, receiverAccountGuid, variables).then (renderedMessage) ->
          mailgunApi.send(siteDefinition.siteName, renderedMessage)

      sendNewLikeNotification: (senderProfileGuid, receiverAccountGuid, variables) ->
        self.renderNewLikeNotification(senderProfileGuid, receiverAccountGuid, variables).then (renderedMessage) ->
          mailgunApi.send(siteDefinition.siteName, renderedMessage)

      sendForgotPasswordNotification: (accountGuid, variables) ->
        self.renderForgotPasswordNotification(accountGuid).then (renderedMessage) ->
          mailgunApi.send(siteDefinition.siteName, renderedMessage)

      sendUnreadMessagesEmail: (accountGuid, variables) ->
        self.renderUnreadMessagesEmail(accountGuid, variables).then (renderedMessage, unreadMessageCount) ->
          mailgunApi.send(siteDefinition.siteName, renderedMessage) if unreadMessageCount > 0

      sendDiscoverNewProfiles: (accountGuid, variables) ->
        self.renderDiscoverNewProfiles(accountGuid, variables).then (renderedMessage, newProfilesToDiscover) ->
          mailgunApi.send(siteDefinition.siteName, renderedMessage) if newProfilesToDiscover > 0
    }

exports.EmailRenderer = ($p, $options) ->
  mincer.logger.use(console) if $options?.debug is true
  basePath = process.cwd()
  environment = new mincer.Environment()
  environment.appendPath(path.join(basePath, 'assets/css'))
  environment.appendPath(path.join(basePath, 'assets/images'))
  environment.appendPath(path.join(basePath, 'assets/lib/ink'))

  shortDate = (date) ->
    return date unless date?
    moment(date).format("MM/DD/YYYY")

  inlineThrottle = throttle(5, 100)
  self = {
    render: (siteId, template, locals) ->
      assetPath = (file) ->
        file = file.replace(/\{siteId\}/g, siteId)
        asset = environment.findAsset(file)
        throw new Error("Unknown asset [#{file}]") unless asset?
        path = "/assets/#{file}"
        path = locals.cdnPrefix + path if locals?.cdnPrefix?
        path
      renderOpts = {
        pretty: true
        assetPath: assetPath
        embedAsset: (file) ->
          asset = environment.findAsset(file)
          asset
      }
      fileName = "views/email/#{siteId}/#{template}.jade"
      locals = _.defaults(locals || {}, renderOpts)
      locals.shortDate = shortDate
      locals.template = template
      locals.href = (href) ->
        href = locals.baseUrl+href if locals.baseUrl?
        parsedHref = url.parse(href, true)
        delete parsedHref.search
        parsedHref.query.auth = locals.auth if locals.auth?
        parsedHref.query.utm_source = 'Existing'
        parsedHref.query.utm_campaign = template
        parsedHref.query.utm_medium = 'Customer Email'
        url.format(parsedHref)
      locals = _.merge {}, locals, {assetPath: assetPath}
      html = jade.renderFile(fileName, locals).toString()
      inlineThrottle ->
        $p.wrap(inline(html, $p.ecb()))
    }
