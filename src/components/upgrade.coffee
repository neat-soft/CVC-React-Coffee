_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
$l = require('./locale')

PaymentMethodForm = createFactory
  getInitialState: -> {}
  handleChange: (e) ->
    field = $(e.target).attr('name')
    value = $(e.target).val()
    @setState(_.object [[field, value]])
  tokenize: ->
    options =
      full_name: @state.name
      year: "20#{@state.year}"
      month: @state.month
    Spreedly.tokenizeCreditCard(options);
    @setState errorMessages: {}
  componentDidMount: ->
    $.getScript "https://core.spreedly.com/iframe/iframe-1.3.min.js", =>
      Spreedly.init()
      Spreedly.on 'ready', =>
        attributes = ['margin-top', 'margin-bottom', 'padding', 'display', 'width', 'background-color', 'border', 'color', 'font-family', 'font-size', 'font-weight']
        styleMap = $(@refs.name.getDOMNode()).css(attributes)
        style = """
          padding: 15px 5px  2px 5px;
          display: inline-block;
          width: 100%;
          background-color: transparent;
          border: 0px;
          color: black;
          font-family: #{styleMap['font-family']};
          font-size: #{styleMap['font-size']};
          font-weight: #{styleMap['font-weight']}
        """.replace(/(\r\n|\n|\r)/gm,'')
        Spreedly.setStyle('number', style)
        Spreedly.setStyle('cvv', style)
        @props.onReady() if @props.onReady?
      Spreedly.on 'paymentMethod', (token, pmData) =>
        @props.onTokenized(token) if @props.onTokenized?
      Spreedly.on 'errors', (errors) =>
        errorMessages = {}
        fieldMap =
          last_name: 'name'
          first_name: 'name'
          number: 'card'
          year: 'expDate'
          month: 'expDate'
        _.each errors, (error) ->
          return unless error.attribute?
          errorMessages[fieldMap[error.attribute] || error.attribute] = $l("upgrade.#{error.key}")
        @setState errorMessages: errorMessages
        @props.onError(errors) if @props.onError?
  componentWillUnmount: ->
    if window.Spreedly?
      Spreedly.removeHandlers()
      Spreedly.unload()
  render: ->
    d.div {className: 'payment-method'},
      d.InputField {ref: "name", name: "name", type: "text", placeholder: "Name", onChange: @handleChange, defaultValue: @state?.name, errorMessage: @state?.errorMessages?.name}
      d.LabeledField {name: 'card', label: "Credit Card Number", errorMessage: @state?.errorMessages?.card}, d.div {id: "spreedly-number", className: 'spreedly-field'}
      d.div {className: 'card-details'},
        d.LabeledField {name: 'exp-date', label: 'Expiration Date', errorMessage: @state?.errorMessages?.expDate},
          d.input {ref: "month", className: 'field-month', name: 'month', type: "number", min: "1", max: "12", placeholder: "MM", onChange: @handleChange, defaultValue: @state?.month}
          d.span {className: 'separator'}, "/"
          d.input {ref: "year", className: 'field-year', name: 'year', type: "number", min: "15", max: "30", placeholder: "YY", onChange: @handleChange, defaultValue: @state?.year}
        d.LabeledField {name: 'cvv', label: "CVV", errorMessage: @state?.errorMessages?.cvv}, d.div {id: "spreedly-cvv", className: 'spreedly-field'}
      d.script {
        'id': "spreedly-iframe"
        'data-environment-key': @props.environmentKey
        'data-number-id': "spreedly-number"
        'data-cvv-id': "spreedly-cvv"
      }

PurchaseCompleted = createFactory
  render: ->
    d.div {className: 'outer-container'}, d.div {className: 'inner-container'},
      d.div {className: 'upgrade-completed'},
        d.div {className: 'message'}, "Your purchase has been completed"
        d.Button {className: 'continue', onClick: @props.onContinue}, "Continue"

exports.PaymentMethod = createFactory
  getInitialState: -> {}
  handleError: ->
    @refs.submitButton.enable()
    @refs.progressBar.hide()
  handleTokenized: (token) ->
    @props.restClient.post "/#{token}", {},
      error: (res, args..., err) =>
        @setState {errorMessage: err?.message || $l("upgrade.genericError")}
        @refs.submitButton.enable()
        @refs.progressBar.hide()
      success: (features) =>
        @props.onUpdateFeatures(features) if @props.onUpdateFeatures?
        @setState {errorMessage: null, completed: true}
  handleTokenize: (e) ->
    e.preventDefault()
    e.stopPropagation()
    @refs.submitButton.disable()
    @refs.paymentMethodForm.tokenize()
    @refs.progressBar.show("Processing Payment", 0)
  handleReady: ->
    @refs.submitButton.enable()
  handleLearnMore: (e) ->
    e.preventDefault()
    $(@refs.learnMore.getDOMNode()).hide()
    $(@refs.disclaimer3.getDOMNode()).show()
  handleHideDisclaimer: (e) ->
    e.preventDefault()
    $(@refs.learnMore.getDOMNode()).show()
    $(@refs.disclaimer3.getDOMNode()).hide()
  handleCustomerSupport: (e) ->
    e.preventDefault()
    @props.onCustomerSupport(e)
  handleContinue: (e) ->
    navigateTo = @props.route.params?.navigateTo || "/browse"
    @props.onChangePath(navigateTo)
  render: ->
    return PurchaseCompleted(onContinue: @handleContinue) if @state?.completed
    d.div {className: 'outer-container'}, d.div {className: 'inner-container'},
      d.ProgressBar {ref: 'progressBar'}
      d.div {className: 'upgrade'},
        d.div {className: "selected-option"}, PricingOption(showTotal: true, type: @props.upgrade.currentOption, option: @props.upgrade.pricing[@props.upgrade.currentOption])
        if @state?.errorMessage?
          d.div {},
            d.div {className: "error-message alert alert-error"}, @state.errorMessage

        d.div {ref: 'paymentMethod', className: 'payment-method-container'},
          PaymentMethodForm {
            ref: 'paymentMethodForm'
            onTokenized: @handleTokenized
            onReady: @handleReady
            onError: @handleError
            environmentKey: @props.upgrade?.environmentKey
          }
          d.div {className: 'disclaimer1'}, $l('upgrade.disclaimer1')
          d.Button {ref: 'submitButton', disabled: true, onClick: @handleTokenize}, "Subscribe Now"
          d.br {}
          d.div {className: 'disclaimers'},
            d.div {className: 'disclaimer2'},
              $l('upgrade.disclaimer2')
              d.a {ref: 'learnMore', className: 'learn-more', href: '#', onClick: @handleLearnMore}, $l('upgrade.learnMore')
            d.br {}
            d.div {ref: 'disclaimer3', className: 'disclaimer3'},
              $l('upgrade.disclaimer3')
              d.a {ref: 'here', className: 'here', href: '#', onClick: @handleCustomerSupport}, $l('upgrade.here')
              $l('upgrade.disclaimer4')
              d.a {ref: 'hide', className: 'hide', href: '#', onClick: @handleHideDisclaimer}, $l('upgrade.hide')

PricingOption = createFactory
  render: ->
    d.div {className: "pricing-option"},
      if @props.option?.flags?.popular and @props.decorate
        d.div {className: 'alert'},
          $l('upgrade.pricing.popular'),
          d.span {className: 'discount'}, @props.option.discount, "%"
      if @props.option?.flags?.bestValue and @props.decorate
        d.div {className: 'alert'},
          $l('upgrade.pricing.bestValue'),
          d.span {className: 'discount'}, @props.option.discount, "%"
      d.span {className: 'description'},
        d.Glyph {glyph: "hand-o-right"} if @props.glyphs
        $l("upgrade.pricing.#{@props.type}")
      d.span {className: 'price'},
        (if @props.option.duration? and !@props.showTotal
          [ d.span {className: "at"}, $l("upgrade.pricing.at")
            "$"
            (Math.round(@props.option.price / @props.option.duration[0]) / 100).toFixed(2)
            d.span {className: 'per-month'}, $l("upgrade.pricing.perMonth")
          ]
        else
          [ "$"
            (@props.option.price / 100).toFixed(2)
          ]
        )...
      d.Glyph {glyph: 'chevron-right'} if @props.glyphs

exports.Upgrade = createFactory
  handleClick: (type, e) ->
    @props.onChangePath("/upgrade/#{type}#{@props.route.qs || ""}")
  render: ->
    pricing = _.map @props.upgrade.pricing, (def, name) ->
      def.name = name
      def
    pricing = _.sortBy(pricing, (def) -> -def.price)
    d.div {className: 'outer-container'}, d.div {className: 'inner-container'},
      d.div {className: 'upgrade'},
        d.h1 {}, $l('upgrade.choosePlan')
        d.ul {className: 'pricing-options'},
          _.map(pricing, (def) =>
            return unless def.standalone
            d.li {className: "button"},
              d.a {onClick: @handleClick.bind(null, def.name)},
                PricingOption({type: def.name, option: def, glyphs: true, decorate: true})
          )...
