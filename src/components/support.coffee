_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
$l = require('./locale')

module.exports = createFactory
  getInitialState: -> {
    message: ""
  }
  show: (animate) ->
    @refs.dialog.show(animate)
  handleCancel: ->
    @replaceState @getInitialState()
    @refs.dialog.hide()
  handleSubmit: ->
    @props.restClient.post '/support', @state, (result) =>
      @handleCancel()
      alert(result.confirmation) if result.confirmation?
  handleChange: (e) ->
    value = $(e.target).val()
    field = $(e.target).attr('name')
    @setState(_.object [[field, value]])
  render: ->
    d.ModalDialog {ref: 'dialog', className: 'support'},
      d.h4 {}, "How can we help you?"
      d.textarea {name: 'message', value: @state.message, placeholder: 'Type your message here', onChange: @handleChange}
      d.div {className: 'buttons'},
        d.Button {onClick: @handleCancel}, "Cancel"
        d.Button {onClick: @handleSubmit}, "Submit"

