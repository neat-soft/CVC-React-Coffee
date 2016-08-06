_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
moment = require('moment')
$l = require('./locale')

exports.ChangePassword = createFactory
  getInitialState: -> {}
  handleChange: (e) ->
    name = $(e.target).attr('name')
    @setState(_.object [[name, $(e.target).val()]])
  handleSave: (e) ->
    return @setState(errorMessage: "Password cannot be blank") unless @state.password?.length > 0
    return @setState(errorMessage: "Password must match") unless @state.password == @state.confirmPassword
    @props.restClient.post '', _.pick(@state, 'password', 'changePassword'),
      success: => @props.onChangePath('/settings')
      error: (res, type, message) => @setState(errorMessage: message)
  render: ->
    d.div {className: 'outer-container change-password'},
      d.div {className: 'inner-container'},
        d.div {className: 'form'},
          d.div {className: "error-message #{unless @state.errorMessage then 'no-error'}"}, @state.errorMessage
          d.InputField {name: 'password', type: 'password', placeholder: "Password", onChange: @handleChange, value: @state.password}
          d.InputField {name: 'confirmPassword', type: 'password', placeholder: "Confirm Password", onChange: @handleChange, value: @state.confirmPassword}
          d.Button {className: "large square", onClick: @handleSave}, "Save"

exports.EmailPreferences = createFactory
  getInitialState: -> _.merge {
    emailAddress: @props.emailAddress
    subscribed: @props.subscribed
  }, _.object _.map @props.preferences, (def, pref) ->
    ["subscribe_#{pref}", 'email' in def.mediums]

  handleChange: (e) ->
    name = $(e.target).attr('name')
    if $(e.target).is('input[type=checkbox]')
      value = $(e.target).is(':checked')
    else
      value = $(e.target).val()
    @setState(_.object [[name, value]])
  handleSave: (e) ->
    return @setState(errorMessage: "E-Mail address cannot be blank") unless @state.emailAddress?.length > 0
    data = _.pick(@state, 'emailAddress', 'subscribed')
    data.preferences = _.object _.map @props.preferences, (def, pref) =>
      [pref, @state["subscribe_#{pref}"]]
    @props.restClient.post '', data,
      success: => @props.onChangePath('/settings')
      error: (res, type, message, errors) =>
        err = errors[0] || errors
        message = $l("settings.#{err.field}.#{err.type}") if err?
        @setState(errorMessage: message)

  render: ->
    d.div {className: 'outer-container email-preferences'},
      d.div {className: 'inner-container'},
        d.div {className: 'form'},
          d.div {className: "error-message #{unless @state.errorMessage then 'no-error'}"}, @state.errorMessage
          d.InputField {name: 'emailAddress', placeholder: "Email Address", onChange: @handleChange, value: @state.emailAddress}
          d.InputField {name: 'subscribed', type: 'checkbox', label: "Yes! I would like to receive emails about the service.", onChange: @handleChange, checked: @state.subscribed}
          (if @state.subscribed
            _.map @props.preferences, (def, pref) =>
              d.InputField {name: "subscribe_#{pref}", type: 'checkbox', label: $l("settings.emailPreferences.#{pref}"), onChange: @handleChange, checked: @state["subscribe_#{pref}"]}
          else
            [d.h4 {}, "You've disabled all emails from CurvesConnect.com!"]
          )...
          d.Button {className: "large square", onClick: @handleSave}, "Save"

exports.RemoveProfile = createFactory
  getInitialState: -> {reason: null}
  handleChange: (e) ->
    name = $(e.target).attr('name')
    @setState(_.object [[name, $(e.target).val()]])
  handleRemove: (e) ->
    #return @setState(errorMessage: "Please tell us why") unless @state.reason?.length > 0
    @props.restClient.post '', _.pick(@state, 'reason'),
      success: =>
      error: (res, type, message) => @setState(errorMessage: message)
  render: ->
    d.div {className: 'outer-container remove-profile'},
      d.div {className: 'inner-container'},
        d.div {className: 'form'},
          d.div {}, d.div {className: "error-message #{unless @state.errorMessage then 'no-error'}"}, @state.errorMessage
          d.Button {className: "large square", onClick: @handleRemove}, "Remove"

exports.ManageSubscription = createFactory
  handleCancel: ->
    @props.restClient.post '/cancel', {}, (result) =>
      @setState subscription: result
  handleStart: ->
    @props.restClient.post '/start', {}, (result) =>
      @setState subscription: result
  handleSubscribe: ->
    @props.onChangePath("/upgrade")
  handleContinue: ->
    @props.onChangePath("/settings")
  render: ->
    total = 0
    subscription = @state?.subscription || @props.subscription
    d.div {className: 'outer-container manage-subscription'},
      d.div {className: 'inner-container'},
        d.div {className: 'info'},
          (if subscription? and subscription?.autoRenew == true
            [ $l("settings.manageSubscription.scheduledToRenewOn")
              d.span {className: 'renewal-date'}, moment(subscription?.expiresOn).format("MM/DD/YYYY")
              d.Button {className: "tiny square cancel", onClick: @handleCancel}, $l("settings.manageSubscription.cancelSubscription")
            ]
          else if subscription?
            [ $l("settings.manageSubscription.notScheduledToRenewOn")
              d.Button {className: "tiny square start", onClick: @handleStart}, $l("settings.manageSubscription.startSubscription")
            ]
          else
            [ $l("settings.manageSubscription.noSubscription")
              d.div {},
                d.Button {className: "square subscribe", onClick: @handleSubscribe}, $l('settings.manageSubscription.subscribe')
            ]
          )...
        d.div {className: 'line-items'},
          _.map(subscription?.lineItems || [], (lineItem) ->
            total+=lineItem.price
            d.div {className: 'line-item'},
              d.span {className: 'label'}, $l("upgrade.pricing.#{lineItem.name}")
              d.span {className: 'value'},
                "$"
                (lineItem.price / 100).toFixed(2)
          )...
          if total > 0
            d.div {className: 'total'},
              d.span {className: 'label'}, $l("settings.manageSubscription.total")
              d.span {className: 'value'},
                "$"
                (total / 100).toFixed(2)
        d.div {},
          d.Button {className: "large square continue", onClick: @handleContinue}, $l("continue")

exports.Settings = createFactory
  render: ->
    d.div {className: 'outer-container settings'},
      d.div {className: 'inner-container'},
        d.Button({className: "square huge", onClick: => @props.onChangePath("/settings/change_password")}, "Change Password")
        d.Button({className: "square huge", onClick: => @props.onChangePath("/settings/email_preferences")}, "Email Preferences")
        d.Button({className: "square huge", onClick: => @props.onChangePath("/settings/manage_subscription")}, "Manage Subscription") if @props.features?.billing
        d.Button({className: "square huge", onClick: => @props.onChangePath("/settings/remove_profile")}, "Remove Profile")
