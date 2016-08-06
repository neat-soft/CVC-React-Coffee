require('intl') if !global.Intl
require('coffee-script/register')
require('source-map-support').install()
{markdown} = require('markdown')
{$p, genericServer, restClient} = require('core')
bodyParser = require('body-parser')
cookieParser = require('cookie-parser')
_ = require('lodash')
fs = require('fs')
url = require('url')
qs = require('querystring')

genericServer.defaultRestServer {maxMemory: 300}, (context) ->
  assetMapping = JSON.parse(fs.readFileSync('lib/assets.json')) if fs.existsSync("lib/assets.json")
  App = require('../components/app')

  cookieMaxAge = 90*24*60*60*1000

  context.registerAll restClient
  context.registerAll require('core').aws
  context.registerAll require('./react_compiler')
  context.registerAll require('./site_definitions')
  context.registerAll require('./emails')
  context.registerAll require('./zendesk')

  context.register 'assetPipeline', ->
    {assetPipeline} = require('core')
    assetPipeline(root: ["./assets", "./public"], assetPrefix: "/assets/")
  context.register 'assetPath', (assetPipeline) -> assetPipeline.assetPath.bind(assetPipeline)

  context.register 'socialApiFactory', ($options, restClientFactory) ->
    baseUrl = $options.baseUrl
    (database) ->
      restClientFactory(_.defaults {baseUrl: "#{baseUrl}/#{database}"}, $options)

  (server) -> context.invoke ($u, $req, $res, scope, scopedVariableFactory, siteDefinitions, assetPath, bootstrapReactApp, assetPipeline, localizedMessages, socialApiFactory, emailProviderFactory, zendeskApi) ->
    $socialApi = scopedVariableFactory('socialApi')
    server.locals.assetPath = assetPath
    server.locals.lookupErrorMessage = (messages, formMessages, fieldName, errorType) ->
      formFieldError = formMessages?.errors?[fieldName]
      if formFieldError?
        return formFieldError if _.isString(formFieldError)
        error = formFieldError[errorType] || formFieldError['INVALID']
      return error if error?
      return formMessages?.errors?[errorType] if formMessages?.errors?[errorType]?
      messages.common.errors[errorType] || messages.common.errors["INVALID"]

    server.use (req, res, next) ->
      userAgent = req.headers['user-agent'] || ""
      deviceType =
        if req.headers['app-type'] == 'android'
          'android-app'
        else if /iPhone|Android|Mobile Safari/.test(userAgent)
          'mobile-site'
        else if /MSIE 9.0|MSIE 8.0|^Mozilla\/4.0 \(compatible; MSIE 6.0;/.test(userAgent)
          'semi-old'
        else if /MSIE 7.0|MSIE 8.0|^Mozilla\/4.0 \(compatible; MSIE 6.0;/.test(userAgent)
          'old-ie'
      req.deviceType = deviceType
      next()

    server.use (req, res, next) ->
      siteKey = siteDefinitions.portMap[req.socket.localPort]
      return res.sendError(500, "Unsupported site on port #{req.socket.localPort}!") unless siteKey?

      return res.sendError(500, "No Database Defined!") unless siteDefinitions[siteKey].socialApiDatabase?
      scope.context.socialApi = socialApiFactory(siteDefinitions[siteKey].socialApiDatabase)

      language = siteDefinitions[siteKey].supportedLanguages[0]
      messages = localizedMessages.getMessages(siteKey)
      res.locals.production = process.env.NODE_ENV == 'production'
      res.locals.siteDefinition = siteDefinitions[siteKey]
      res.locals.siteDefinition.siteKey = siteKey
      res.locals.language = language
      res.locals.siteClass = siteKey
      res.locals.siteId = siteKey
      res.locals.messages = messages
      res.locals.pretty = true;
      $p.when(emailProviderFactory(res.locals.siteDefinition)).then (emailProvider) ->
        req.emailProvider = emailProvider
        next()

    server.use "/assets", assetPipeline.createServerModule()

    server.set('view engine', 'jade');
    server.use(bodyParser.urlencoded(extended: true))
    server.use(cookieParser())
    server.use (req, res, next) ->
      req.locale = req.params.locale || "en"
      next()

    server.use (req, res, next) ->
      type = if req.accepts('html') != 'html' then "REST" else "HTML"
      server.$logger.tagScope(type)
      server.$logger.info req.url, {query: req.query, headers: req.headers, cookies: req.cookies}
      next()

    forwardCookies = ['tg', 'token']
    forwardHeaders = ['referer']

    server.use (req, res, next) ->
      #delete req.cookies['token'] #unless req.accepts('html') == 'html'
      cookies = req.headers['local-cookies']
      if cookies?
        cookies = JSON.parse(cookies)
        cookies = _.pick cookies, forwardCookies
        _.each cookies, (v, k) ->
          req.cookies[k] = v
      next()

    server.use (req, res, next) ->
      proto = req.headers['x-forwarded-proto'] || "http"
      server.options = context.config?.server
      #server.options?.forceHttps = true
      res.redirectWithCookies = (redirectTo, query) ->
        redirect = _.merge [
          query || {}
          _.pick(req.cookies, forwardCookies...)
          _.pick(req.headers, forwardHeaders...)
        ]...
        redirect.sig = $u.objectHmac server.options.forwardHmacKey, redirect
        redirectQuery = qs.stringify(redirect)
        redirectTo = "#{redirectTo}?#{redirectQuery}"
        res.redirect(redirectTo)

      if (server.options?.forceHttps and req.method == 'GET' and proto? and proto.toLowerCase() != 'https') or (req.headers['host'] || "").match(/^www/)?
        forward = _.merge [
          _.omit(req.query, forwardCookies.join(forwardHeaders))
          _.pick(req.cookies, forwardCookies...)
          _.pick(req.headers, forwardHeaders...)
        ]...
        forward.sig = $u.objectHmac server.options.forwardHmacKey, forward
        desiredProto = proto
        parsedHost = url.parse(req.headers['host']) if req.headers['host']?
        desiredProto = parsedHost.protocol
        desiredProto = if server.options?.forceHttps then "https" else 'http'
        parsedUrl = url.parse(req.originalUrl)
        basePath = parsedUrl.path.replace(/\?.*/, '')
        forwardQuery = qs.stringify(forward)
        forwardTo = "#{desiredProto}://#{res.locals.siteDefinition.siteUrl}#{basePath}?#{forwardQuery}"
        return res.redirect(forwardTo)
      next()

    server.use (req, res, next) ->
      if req.query.sig?
        query = _.omit(req.query, 'sig')
        if req.query.sig == $u.objectHmac(server.options.forwardHmacKey, query)
          _.each _.pick(query, forwardCookies), (v, k) ->
            req.cookies[k] = v
            res.cookie(k, v, { httpOnly: true, maxAge: cookieMaxAge })
          _.each _.pick(query, forwardHeaders), (v, k) -> req.headers[k] = v
      next()

    server.use (req, res, next) ->
      res.locals.form?= if req.method == 'POST' then req.body else {}
      res.locals.form.errors = {}
      next()

    server.use (req, res, next) ->
      req.clientInfo = ->
        forwardedFor = req.headers['HTTP_X_FORWARDED_FOR'] || req.headers['x-forwarded-for']
        if forwardedFor?
          forwardedFor = forwardedFor.split(',')
          forwardedFor = forwardedFor[forwardedFor.length - 1].trim()
        return {
          source: req.query['utm_source'] || req.query['source'] || req.query['src']
          campaign: req.query['utm_campaign'] || req.query['campaign']
          creative: req.query['creative']
          ipAddress: forwardedFor || req.connection.remoteAddress
          userAgent: req.headers['user-agent']
          referrer: req.headers['referer']
        }
      next()

    server.route('/robots.txt')
      .get (req, res) ->
        res.setHeader('content-type', 'text/plain')
        res.send("")

    server.route('/country')
      .get (req, res) ->
        res.render('country', noHelp: true)

    server.use (req, res, next) ->
      if req.cookies['tg'] and req.cookies['tg']?.length > 0
        server.$logger.tagScope req.cookies['tg'].substring(0, 7)
      next()

    _route = server.route
    server.route = (args...) ->
      setTransactionName = (req, res, next) ->
        if server.locals.newrelic?.setTransactionName?
          server.locals.newrelic.setTransactionName("[#{req.method}] #{_.flatten([req.route.path])[0]}")
        next()
      _route.apply(server, args).all(setTransactionName)

    server.route('/')
      .get (req, res, next) ->
        return next() unless req.cookies['token']?
        res.redirect('/app/browse')
      .all (req, res, next) ->
        hit = req.clientInfo()
        ($p.when(
          if req.cookies['tg']?
            $socialApi().get("/tracking", req.cookies['tg'], {ipAddress: hit.ipAddress})
        ).then (validCookie) ->
          return if validCookie
          if req.accepts('html') != 'html'
            server.$logger.error("REST REQUEST WITHOUT A TRACKING COOKIE", {headers: req.headers, query: req.query, cookies: req.cookies})
            return
          if req.cookies['tg']?
            server.$logger.error("RESETTING INVALID COOKIE", {headers: req.headers, query: req.query, cookies: req.cookies})
          $socialApi().put('/tracking', hit).then (guid) ->
            server.$logger.debug "NEW HIT", guid
            res.cookie('tg', guid, { httpOnly: true, maxAge: cookieMaxAge }) if guid?
            req.cookies['tg'] = guid
            res.locals.confirmTrackingGuid = guid
        ).then
          success: -> next()
          error: (err) ->
            return $p.error(err) if err.statusCode >= 500
            errors = err
            errors = errors.errors if errors?.errors?
            errors = _.flatten([errors])
            errors = _.indexBy(errors, 'field')
            if errors.ipAddress?.type == 'INVALID'
              req.invalidIpAddress = true
              return next()
            $p.error(err)
      .post (req, res, next) ->
        #Let's try to signin first
        #return res.redirect('/country') if req.invalidIpAddress
        return next() unless req.body.emailAddress?.length > 0 and req.body.password?.length > 0
        $socialApi().post('/authenticate/email', {emailAddress: req.body.emailAddress, password: req.body.password, trackingGuid: req.cookies['tg']}).then
          success: (result) ->
            return res.rediect('/') unless result.loginToken?
            res.cookie('token', result.loginToken, { httpOnly: true, maxAge: cookieMaxAge})
            req.cookies['token'] = result.loginToken
            res.redirect('/app/browse')
          error: (err) ->
            next()
      .post (req, res, next) ->
        return next() unless req.body.profileData?
        req.body = JSON.parse(req.body.profileData)
        req.body.genders = "#{req.body.gender}#{req.body.lookingFor?.gender}"
        next()
      .post (req, res, next) ->
        account = _.pick(req.body, 'emailAddress', 'password', 'referralCode')
        account.firstHitGuid = req.cookies['tg'] || "INVALID"
        profile = {
          postalCode: req.body.postalCode
          age: parseInt(req.body.age)
          gender: req.body.genders[0]
          lookingFor:
            gender: req.body.genders[1]
        }
        $socialApi().put('/register', {account: account, profile: profile, ipAddress: req.clientInfo().ipAddress}).then
          success: (result) ->
            if result.loginToken?
              $p.when(emailProviderFactory(res.locals.siteDefinition)).then (emailProvider) ->
                emailProvider.sendWelcomeEmail(result.guid, {password: result.password})
                res.cookie('token', result.loginToken, { httpOnly: true, maxAge: cookieMaxAge })
                req.cookies['token'] = result.loginToken
                [
                  ($socialApi().put('/photos', result.profileGuid, 'import', req.body.photos) if req.body.photos?)
                  ($socialApi().post('/profiles', result.profileGuid, {content: req.body.content, advancedCriteria: req.body.advancedCriteria}) if req.body.content?)
                ].then ->
                  if req.body.photos?
                    res.redirect('/app/browse')
                  else
                    res.redirect('/app/photos?continueTo=/browse')
            else
              res.redirect('/')
          error: (err) ->
            return next() if err.statusCode >= 500
            errors = err
            errors = errors.errors if errors?.errors?
            errors = _.flatten([errors])
            errorMap = {}
            _.each errors, (error) ->
              errorMap[error.field] = error.type unless errorMap[error.field]?
            if errorMap['emailAddress'] == 'ACCOUNT_REMOVED'
              res.redirect("/reinstate?email_address=#{account.emailAddress}")
            else
              res.locals.form.errors = errorMap
              next()

      .all (req, res) ->
        res.render('landing_pages/shared')

    server.route('/tg/:guid.gif')
      .get (req, res) ->
        $socialApi().put('/tracking', req.params.guid, 'confirm').then ->
          res.set('Content-Type', 'image/gif')
          pixel = new Buffer("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", 'base64')
          res.send(pixel)


    server.route('/not_enough_members')
      .get (req, res) ->
        res.locals.fullScreenErrorMessage="notEnoughUsers"
        res.render('landing_pages/shared')

    server.route('/reinstate')
      .get (req, res) ->
        res.render('reinstate',  emailAddress: req.query.email_address)
      .post (req, res) ->
        $socialApi().post('/accounts/email_address/reinstate', emailAddress: req.body.emailAddress).then
          success: (results) ->
            req.emailProvider.sendForgotPasswordNotification(results.guid).then ->
              res.locals.fullScreenErrorMessage="reinstateConfirmation"
              res.render('landing_pages/shared')
          error: (err) ->
            res.redirect('/')

    server.route('/signin')
      .get (req, res, next) ->
        return next() unless req.cookies['token']?
        res.redirect('/app/browse')

      .post (req, res, next) ->
        $socialApi().post('/authenticate/email', {emailAddress: req.body.emailAddress, password: req.body.password, trackingGuid: req.cookies['tg']}).then
          success: (result) ->
            if result.loginToken?
              res.cookie('token', result.loginToken, { httpOnly: true, maxAge: cookieMaxAge })
              req.cookies['token'] = result.loginToken
              params = _.pick req.cookies, forwardCookies
              params.sig = $u.objectHmac server.options.forwardHmacKey, params
              res.redirect("/app/browse?#{qs.stringify(params)}")
            else
              res.redirect('/not_enough_members')
          error: (err) ->
            return $p.error(err) if err.statusCode >= 500
            errors = err
            errors = errors.errors if errors?.errors?
            errors = _.flatten([errors])
            errorMap = {}
            _.each errors, (error) ->
              errorMap[error.field] = error.type unless errorMap[error.field]?
            if errorMap['emailAddress'] == 'ACCOUNT_REMOVED'
              res.redirect("/reinstate?email_address=#{req.body.emailAddress}")
            else
              res.locals.form.errors = errorMap
              next()
      .all (req, res) ->
        res.render('signin')

    server.route('/signout')
      .post (req, res, next) ->
        if req.cookies['token']?
          res.clearCookie('token')
        res.redirect('signin')

    server.route('/forgot_password')
      .post (req, res, next) ->
        $socialApi().post('/accounts/email_address', emailAddress: req.body.emailAddress).then
          success: (results) ->
            req.emailProvider.sendForgotPasswordNotification(results.guid).then ->
            res.locals.fullScreenErrorMessage="forgotPasswordSent"
            res.render('landing_pages/shared')
          error: (err) ->
            return $p.error(err) if err.statusCode >= 500
            errors = err
            errors = errors.errors if errors?.errors?
            errors = _.flatten([errors])
            errorMap = {}
            _.each errors, (error) ->
              errorMap[error.field] = error.type unless errorMap[error.field]?
            res.locals.form.errors = errorMap
            next()
      .all (req, res) ->
        res.render('forgot_password')

    staticCache = {}
    server.route(['/privacy_policy', '/tos', '/about_us', '/faq'])
      .get (req, res, next) ->
        parsedUrl = url.parse(req.url)?.pathname
        page = parsedUrl.replace(/^\//,'')
        siteId = res.locals.siteId
        path = "static/#{siteId}/#{page}.md"
        content = staticCache[path]
        if !content? or process.env.NODE_ENV=="development"
          content = staticCache[path] = fs.readFileSync(path).toString()
        res.render('static', content: markdown.toHTML(content, 'Maruku'))

    server.use (req, res, next) ->
      token = req.query.auth || req.cookies['token']
      return res.redirectWithCookies("/signin") unless token?
      $socialApi().post('/authenticate/token', {token: token, trackingGuid: req.cookies['tg']}).then
        error: (err) ->
          server.$logger.error err
          return res.sendError(500, "Site is currently unavailable, please try again") if err.code == 'ECONNREFUSED'
          res.clearCookie('token')
          res.redirect("/signin")
        success: (result) ->
          server.$logger.tagScope result.guid.substring(0, 7)
          req.accountGuid = result.guid
          res.cookie('token', result.loginToken, { httpOnly: true, maxAge: cookieMaxAge })
          req.cookies['token'] = result.loginToken
          if req.query.auth?
            parsedUrl = url.parse(req.url)
            newUrl = {
              pathname: parsedUrl.pathname
              search: qs.stringify(_.omit(req.query, 'auth'))
            }
            return res.redirect(url.format(newUrl))
          $socialApi().get("/profiles/by_account/#{result.guid}").then (result) ->
            req.profileGuid = result
            next()

    server.route('/unsubscribe/:emailType').get (req, res) ->
      $p.when(
        if req.params.emailType == 'all'
          $socialApi().put('/accounts', $req().accountGuid, 'unsubscribe')
        else
          $socialApi().get('/notification_preferences', $req().accountGuid).then (newPreferences) ->
            def = newPreferences[req.params.emailType]
            if def?
              def.mediums = _.without(def.mediums, 'email')
              $socialApi().put('/notification_preferences', $req().accountGuid, newPreferences)
      ).then ->
          res.redirect("/app/settings/email_preferences")

    if process.env.NODE_ENV=="development"
      server.route('/email/welcome').get (req, res) ->
        $p.when(emailProviderFactory(res.locals.siteDefinition)).then (emailProvider) ->
          emailProvider.renderWelcomeEmail(req.accountGuid, {password: "test"}).then (result) ->
            res.send(result.html)
      server.route('/email/unread').get (req, res) ->
        $p.when(emailProviderFactory(res.locals.siteDefinition)).then (emailProvider) ->
          emailProvider.renderUnreadMessagesEmail(req.accountGuid).then (result) ->
            res.send(result.html)
      server.route('/email/new_message/:toProfileGuid').get (req, res) ->
        $p.when(emailProviderFactory(res.locals.siteDefinition)).then (emailProvider) ->
          emailProvider.renderNewMessageNotification(req.accountGuid, req.params.toProfileGuid).then (result) ->
            res.send(result.html)

    ##### REACT APP #####
    server.route(['/app', '/app(/*)'])
      .all (req, res, next) ->
        path = req.params[0] || "/"
        version = assetPath("client/app_client.js").match(/.*app_client-(.*).js/)?[1]
        req.state = {
          path: path
          version: version
          profileGuid: req.profileGuid
        }
        redirect = res.redirect
        res.redirect = (redirectTo) ->
          return redirect.apply(res, ["/app#{redirectTo}"]) if req.accepts('html') == 'html'
          req.state?={}
          req.state._redirectTo = redirectTo
          res.send(req.state)
        [ $socialApi().get('/features', req.accountGuid)
        ].then (features) ->
          req.features = features
          next()

    server.post '/javascript_error', (req, res) ->
      server.$logger.warn "[JAVASCRIPT] #{req.body.message}\n#{req.headers['user-agent']}\n#{(if req.body.stackTrace? then "\n"+req.body.stackTrace else "")}"
      res.send({status: "OK"})

    rest = server.rest.nest('/app')

    searchProfiles = (filter, page, pageSize) ->
      filter = _.merge {}, filter, {
        hasPicture: true
        banned: false
        prankster: false
        ignored: false
        profileGuid: $req().state.profileGuid
      }
      $socialApi().post('/profiles/search', criteria: filter, sortBy: [field: 'distance', dir: 'asc'], pageSize: pageSize, page: page)

    rest.get '/discover', ($next) ->
      $socialApi().post('/discovery', $req().state.profileGuid).then (results) ->
        $req().state.discover = {
          totalFound: results.totalFound
          items: results.profiles
        }
        $next()

    rest.post '/discover', ($next) ->
      skipProfiles = $req().body?.skipProfiles
      $socialApi().post('/discovery', $req().state.profileGuid, {skipProfiles: skipProfiles})


    rest.post '/discover/like/:guid', (guid) ->
      guid = guid.isPresent().value()
      $socialApi().put('/index/like_profile', $req().state.profileGuid, guid).then -> {}

    rest.post '/discover/hide/:guid', (guid) ->
      guid = guid.isPresent().value()
      $socialApi().put('/index/maybe_profile', $req().state.profileGuid, guid).then -> {}

    registerProfileActions = (baseUrl, restEndPoint) ->
      restEndPoint.post "#{baseUrl}/like/:guid", (guid) ->
        guid = guid.isPresent().value()
        $socialApi().put('/index/like_profile', $req().state.profileGuid, guid).then -> {}

      restEndPoint.post "#{baseUrl}/unlike/:guid", (guid) ->
        guid = guid.isPresent().value()
        $socialApi().put('/index/unlike_profile', $req().state.profileGuid, guid).then -> {}

      restEndPoint.post "#{baseUrl}/hide/:guid", (guid) ->
        guid = guid.isPresent().value()
        $socialApi().put('/index/hide_profile', $req().state.profileGuid, guid).then -> {}

      restEndPoint.post "#{baseUrl}/block/:guid", (guid) ->
        guid = guid.isPresent().value()
        $socialApi().put('/index/block_profile', $req().state.profileGuid, guid).then -> {}

    rest.get '/liked_by', ($next) ->
      $next()

    rest.post '/liked_by', (page, pageSize) ->
      page = page.intValue()
      pageSize = pageSize.intValue() || 20
      $socialApi().get('/discovery', $req().state.profileGuid, 'liked_by', {page: page, pageSize: pageSize, markAsViewed: true}).then (results) ->
        {items: results.profiles, totalFound: results.totalFound}

    registerProfileActions("/liked_by", rest)

    rest.get '/visitors', ($next) ->
      $next()

    rest.post '/visitors', (page, pageSize) ->
      page = page.intValue()
      pageSize = pageSize.intValue() || 20
      $socialApi().get('/visitors', $req().state.profileGuid, {page: page, pageSize: pageSize, markAsViewed: true}).then (results) ->
        {items: results.profiles, totalFound: results.totalFound}

    registerProfileActions("/visitors", rest)

    rest.get '/browse', ($next) ->
      $socialApi().get('/profiles', $req().state.profileGuid).then (profile) ->
        filter =
          gender: profile.lookingFor.gender
          minAge: Math.max(18, profile.lookingFor.minAge - 5)
          maxAge: Math.min(99, profile.lookingFor.maxAge + 5)
          lookingFor:
            gender: profile.gender
        searchProfiles(filter, 1, 10).then (results) ->
          $req().state.browse = {
            defaultFilter: filter
            totalFound: results.totalFound
            items: results.profiles
          }
          $next()

    rest.post '/browse', (filter, page, pageSize, $next) ->
      filter=filter.isPresent().value()
      page=page.intValue()
      pageSize=pageSize.intValue()
      searchProfiles(filter, page, pageSize).then (results) ->
        $res().send({totalFound: results.totalFound, items: results.profiles})

    getProfile = (guid) ->
      [ $socialApi().get('/profiles', guid)
        $socialApi().get('/discovery/status', $req().state.profileGuid, guid)
      ].then (profile, discoverStatus) ->
        return profile unless profile?
        profile.flags = {
          liked: discoverStatus[guid]?.liked
          hidden: discoverStatus[guid]?.hidden
        }
        profile

    rest.get '/profile/:guid', (guid, $next) ->
      guid = guid.isPresent().value()
      getProfile(guid).then (profile) ->
        $socialApi().put('/visitors', guid, $req().state.profileGuid).then ->
          $req().state.profile = {profile: profile}
          $next()

    rest.post '/profile/:guid/like', (guid) ->
      guid = guid.isPresent().value()
      $socialApi().put('/index/like_profile', $req().state.profileGuid, guid).then ->
        getProfile(guid).then (profile) ->
          $res().send(profile)

    rest.post '/profile/:guid/unlike', (guid) ->
      guid = guid.isPresent().value()
      $socialApi().put('/index/unlike_profile', $req().state.profileGuid, guid).then ->
        getProfile(guid).then (profile) ->
          $res().send(profile)

    rest.post '/profile/:guid/hide', (guid) ->
      guid = guid.isPresent().value()
      $socialApi().put('/index/hide_profile', $req().state.profileGuid, guid).then ->
        getProfile(guid).then (profile) ->
          $res().send(profile)

    rest.post "/profile/:guid/report", (guid, reason) ->
      guid = guid.isPresent().value()
      reason = reason.isPresent().value()
      $socialApi().post('/index/report', $req().state.profileGuid, guid, {reason: reason}).then -> {}

    rest.post '/myprofile', ($next) ->
      $socialApi().post('/profiles', $req().state.profileGuid, $req().body).then (profile) ->
        $req().state.profile = {profile: profile}
        $next()

    rest.get '/myprofile', ($next) ->
      $socialApi().get('/profiles/private', $req().state.profileGuid).then (profile) ->
        $req().state.profile = {profile: profile}
        $next()

    rest.get '/locations/:postalCode', (postalCode) ->
      postalCode = postalCode.isPresent().value()
      $socialApi().get('/profiles/search_locations', "US", postalCode)

    multipart = require('connect-multiparty')
    raw = bodyParser.raw(type: 'image/*', limit: '50mb')
    server.post '/app/photos', (req, res, next) ->
      if req.is('image/*')
        raw(req, res, next)
      else
        multipart()(req, res, next)

    server.post '/app/photos', (req, res, next) ->
      if server.locals.newrelic?.setTransactionName?
        server.locals.newrelic.setTransactionName("[#{req.method}] /app/photos")
      return next() unless req.files?.photo?.path? or req.is('image/*')
      if req.is('image/*')
        data = req.body
      else
        data = fs.readFileSync(req.files.photo.path)
      $socialApi().put("/photos/#{$req().state.profileGuid}/primary", data).then
        success: (results) ->
          return res.send({status: 'OK'}) if req.is('image/*')
          return res.redirect(req.body.continueTo) if req.body.continueTo?.length > 0
          res.redirect("/photos")
        error: (err) ->
          req.state.errorMessage = "Unable to upload photo"
          next()

    rest.delete '/photos', (guid, $next) ->
      guid = guid.isPresent().value()
      $socialApi().delete("/photos", $req().state.profileGuid, guid).then ->
        $next()

    rest.post '/photos/make_primary', (guid, $next) ->
      guid = guid.isPresent().value()
      $socialApi().post("/photos", $req().state.profileGuid, guid, "album", {album: 'primary'}).then ->
        $next()

    rest.all ['/photos', '/photos/*'], (continueTo, $next) ->
      continueTo = continueTo.value()
      $socialApi().get("/photos/#{$req().state.profileGuid}").then (photos) ->
        photos = _.sortBy photos, (photo) -> if photo.album == 'primary' then "0#{photo.guid}" else "1#{photo.guid}"
        $req().state.photos = {photos: photos, continueTo: continueTo}
        $next()

    rest.post '/inbox', (page, pageSize) ->
      page=page.intValue() || 1
      pageSize=pageSize.intValue()
      $socialApi().get('/messaging/inbox', $req().state.profileGuid, page, pageSize: pageSize).then (results) ->
        $res().send {totalFound: results.total, items: results.list}

    rest.post '/inbox/:convWithGuid/delete', (convWithGuid, $next) ->
      convWithGuid = convWithGuid.isPresent().value()
      $socialApi().delete('/messaging/conversation', $req().state.profileGuid, convWithGuid).then ->
        $res().send(status: "OK")

    rest.get '/conversation/:convWithGuid', (convWithGuid, $next) ->
      convWithGuid = convWithGuid.isPresent().value()
      return $res().redirect("/upgrade?navigateTo=/conversation/#{encodeURIComponent(convWithGuid)}") if $req().features?.messaging?.available!=true
      [ $socialApi().get('/profiles', convWithGuid)
        $socialApi().get('/messaging/conversations', $req().state.profileGuid, convWithGuid, markAsRead: true)
      ].then (profileSummary, messages) ->
        $req().state.conversation = {
          conversation:
            conversationWithGuid: convWithGuid
            profileSummary: profileSummary
            messages: messages
        }
        $next()

    rest.put '/conversation/:convWithGuid', (convWithGuid, text) ->
      convWithGuid = convWithGuid.isPresent().value()
      text = text.isPresent().value()
      $socialApi().put('/messaging/conversation', $req().state.profileGuid, convWithGuid, text:text).then ->
        $res().send(status: "OK")

    rest.get '/settings', ($next) ->
      $next()

    rest.post '/settings/change_password', (password, $next) ->
      password = password.isPresent().value()
      $socialApi().put('/accounts', $req().accountGuid, 'password', {password: password}).then ->
        $next()

    rest.get '/settings/manage_subscription', ($next) ->
      $socialApi().get('/billing', $req().accountGuid, 'subscription').then (subscription) ->
        $req().state.subscription = {
          subscription: subscription
        }
        $next()

    rest.post '/settings/manage_subscription/cancel', () ->
      $socialApi().put('/billing', $req().accountGuid, 'subscription', 'cancel')

    rest.post '/settings/manage_subscription/start', () ->
      $socialApi().put('/billing', $req().accountGuid, 'subscription', 'start')

    rest.get '/settings/email_preferences', ($next) ->
      [ $socialApi().get('/accounts', $req().accountGuid)
        $socialApi().get('/notification_preferences', $req().accountGuid)
      ].then (account, preferences) ->
        $req().state.emailPreferences = {
          emailAddress: account.emailAddress
          subscribed: !account.unsubscribed
          preferences: preferences
        }
        $next()

    rest.post '/settings/email_preferences', (emailAddress, subscribed, preferences, $next) ->
      emailAddress = emailAddress.isPresent().value()
      unsubscribed = subscribed.value() == 'false'
      preferences = preferences.value()
      [ $socialApi().get('/notification_preferences', $req().accountGuid)
        $socialApi().put('/accounts', $req().accountGuid, 'email_preferences', {emailAddress: emailAddress, unsubscribed: unsubscribed}).then ->
      ].then (newPreferences) ->
        _.each newPreferences, (def, pref) ->
          if preferences[pref]?
            if preferences[pref] == 'true'
              def.mediums = _.uniq(def.mediums.concat(['email']))
            else
              def.mediums = _.without(def.mediums, 'email')
        $socialApi().put('/notification_preferences', $req().accountGuid, newPreferences).then ->
          $next()

    rest.post '/settings/remove_profile', ($next) ->
      $socialApi().delete('/accounts', $req().accountGuid).then ->
        $res().setHeader("change-location", "/")
        $res().send($req().state || {})

    rest.post '/support', (message) ->
      message = message.value()
      return $res().send({}) unless message?.length > 0
      [ $socialApi().get('/accounts', $req().accountGuid)
        $socialApi().get('/profiles/private', $req().state.profileGuid)
      ].then (account, profile) ->
        info = $req().clientInfo()
        accountIdentifier = ($req().accountGuid || "").substring(0,6)
        zendeskApi.createTicket(profile.username, info.ipAddress, info.userAgent, accountIdentifier, account.emailAddress, message).then
          error: -> $res().send({confirmation: 'Unable to submit message at this time, please try again later.'})
          success: -> $res().send({confirmation: 'Your message has been submitted!'})

    rest.get ['/upgrade', '/upgrade(/*)'], ($next) ->
      $socialApi().get('/billing', $req().accountGuid, 'pricing').then (pricing) ->
        $req().state.upgrade = {
          upgrade:
            pricing: pricing
        }
        $req().state.path+="?navigateTo=#{decodeURIComponent($req().query.navigateTo)}" if $req().query.navigateTo?
        $next()

    rest.get '/upgrade/:option', (option, $next) ->
      option = option.isPresent().value()
      $socialApi().get('/billing/spreedly/environment_key').then (key) ->
        _.merge $req().state.upgrade.upgrade, {
          currentOption: option
          environmentKey: key
        }
        $next()

    rest.post '/upgrade/:option/:token', (option, token) ->
      option = option.isPresent().value()
      token = token.isPresent().value()
      $socialApi().post('/billing', $req().accountGuid, "complete_purchase", {option: option, token: token}).then (result) ->
        $socialApi().get('/features', $req().accountGuid)

    server.route(['/app', '/app(/*)'])
      .all (req, res, next) ->
        [ $socialApi().get('/messaging/inbox', req.state.profileGuid, 1, unreadOnly: true, pageSize: 0)
          $socialApi().get('/discovery', req.state.profileGuid, "count")
          $socialApi().get('/visitors', req.state.profileGuid, "unviewed_count")
          $socialApi().get('/discovery', req.state.profileGuid, "liked_by", "count")
        ].then (inbox, discover, visitors, likedBy) ->
          req.state.counters = {
            newMessages: inbox?.total
            newDiscover: discover?.count
            newLikedBy: likedBy.totalUnviewed
            newVisitors: visitors.totalUnviewed
          }
          req.state.features = req.features
          return res.send(req.state || {}) unless req.accepts('html') == 'html'
          req.state.cookies = _.pick(req.cookies, forwardCookies)
          req.state.messages=res.locals.messages['app']
          req.state.messages.genericPhotos = {F: assetPath('generic-female.png'), M: assetPath('generic-male.png')}
          $socialApi().get('/profiles/private', $req().state.profileGuid).then (myProfile) ->
            req.state.myProfileSummary=myProfile
            res.send(bootstrapReactApp(App, "client/app_client.js", "app.css", req.state))

    monitorQueue = (queue, def, block) ->
      console.log "MONITORING", queue, def.socialApiDatabase
      socialApi = socialApiFactory(def.socialApiDatabase)
      doIt = ->
        (socialApi.get('/queue_bridge', queue, {waitTime: 10, retryIn: 60, count: 1}).then (items) ->
          processedRefs = []
          (_.map items, (item, ref) ->
            server.$logger.info "[#{def.siteKey}][#{queue}]", item
            $p.when(block(item)).then
              success: -> processedRefs.push(ref)
              error: (err) -> server.$logger.error "[#{def.siteKey}][#{queue}] Error [#{err.message || err}] while processing", item
              failure: (err) -> server.$logger.error "[#{def.siteKey}][#{queue}] Failure [#{err.message || err}] while processing", item
          ).then ->
            $p.when(socialApi.delete('/queue_bridge', queue, processedRefs.join(',')) if processedRefs.length > 0)
        ).then
          success: -> doIt()
          error: -> setTimeout doIt, 300
        null
      doIt()
      doIt()

    _.each siteDefinitions, (def, name) ->
      if !def.disableQueueMonitoring and def.socialApiDatabase?
        def.siteKey = name
        [ $p.when(emailProviderFactory(def))
          $p.when(socialApiFactory(def.socialApiDatabase))
        ].then (emailProvider, socialApi) ->
          instantNotifications = {
            message_notification: (notification) -> emailProvider.sendNewMessageNotification(notification.aboutProfileGuid, notification.accountGuid)
            like_notification: (notification) -> emailProvider.sendNewLikeNotification(notification.aboutProfileGuid, notification.accountGuid)
          }
          batchNotifications = {
            unread_messages: (notification) -> emailProvider.sendUnreadMessagesEmail(notification.accountGuid)
            discover_new_profiles: (notification) -> emailProvider.sendDiscoverNewProfiles(notification.accountGuid)
          }
          monitorQueue 'NOTIFICATIONS:INSTANT', def, (notification) ->
            return $p.error("Unknown notification [#{notification.type}]") unless instantNotifications[notification.type]?
            return unless 'email' in notification.mediums
            instantNotifications[notification.type](notification).then ->
              socialApi.put('/notifications', notification.profileGuid, notification.aboutProfileGuid, notification.type) if notification.profileGuid? and notification.aboutProfileGuid?
          monitorQueue 'NOTIFICATIONS:BATCH', def, (notification) ->
            return $p.error("Unknown notification [#{notification.type}]") unless batchNotifications[notification.type]?
            return unless 'email' in notification.mediums
            batchNotifications[notification.type](notification).then ->
              socialApi.put('/notifications', notification.profileGuid, notification.type) if notification.profileGuid?
