jade = require('jade')
_ = require('lodash')
exports.BootstrapReactApp = (assetPath, $req, $res) ->
  react = require("react")
  $d = react.DOM
  (reactAppFactory, javascriptLocation, stylesheetLocation, initialState) ->
    initialStateJson = JSON.stringify initialState, (key, value) ->
      return value.toString() if value instanceof RegExp
      value
    head = $d.head {}, [
      $d.link {rel: "shortcut icon", href: assetPath("favicon.ico")}
      $d.link {rel: "stylesheet", type: "text/css", href: assetPath(stylesheetLocation)}
      $d.meta {name: "viewport", content:"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=1"}
      $d.meta {name: "mobile-web-app-capable", content:"yes"}
      $d.meta {name: "apple-mobile-web-app-capable", content:"yes"}
      $d.meta {name: "mobile-web-app-status-bar-style", content: "black-translucent"}
      $d.meta {name: "apple-mobile-web-app-status-bar-style", content: "black-translucent"}
      $d.script {id: "initial-state", type: 'application/json', dangerouslySetInnerHTML: {__html: initialStateJson}}
    ]...
    body = $d.body {style:width:'100%',height:'100%'}, [
      #$d.section {id: "app", dangerouslySetInnerHTML: {__html: react.renderToString(reactAppFactory(initialState))}}
      $d.section {id: "app"}
      #$d.script {type: "application/javascript", src: assetPath('zepto.js')} #unless process.env.NODE_ENV=='production'
      $d.script {type: "application/javascript", src: assetPath('jquery.js')} #unless process.env.NODE_ENV=='production'
      $d.script {type: "application/javascript", src: assetPath('jquery.autogrow.js')} #unless process.env.NODE_ENV=='production'
      $d.script {type: "application/javascript", src: assetPath('jquery.resize.js')} #unless process.env.NODE_ENV=='production'
      $d.script {type: "application/javascript", src: assetPath('client/common_libs.js')} #unless process.env.NODE_ENV=='production'
      $d.script {type: "application/javascript", src: assetPath(javascriptLocation)}
      $d.div {dangerouslySetInnerHTML: {__html: jade.renderFile('views/layouts/external_scripts.jade', _.merge({app: true}, $res().locals)).toString()}}
    ]...

    html = $d.html {}, [
      head
      body
    ]...
    react.renderToStaticMarkup(html)