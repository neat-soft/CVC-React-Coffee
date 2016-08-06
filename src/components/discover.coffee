_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas'), require('./profile_list')
{createFactory} = d
stores = require('./stores')
$l = require('./locale')
moment = require('moment')

exports.Discover = createFactory
  getDefaultProps: -> {
    store: new stores.DiscoverStore()
  }
  handleChange: ->
    @props.notificationStore.updateDiscoverCounter(@props.store.getTotalFound())
    @forceUpdate()
  handleViewProfile: ->
    @props.onChangePath("/profile/#{@props.store.getCurrentProfile().guid}")
  handleSendMessage: ->
    @props.onChangePath("/conversation/#{@props.store.getCurrentProfile().guid}")
  componentWillMount: ->
    @props.store.preload(@props.items, @props.totalFound)
  componentDidMount: ->
    @props.store.on 'change', @handleChange
    @props.store.setRestClient(@props.restClient)
  componentWillUnmount: -> @props.store.removeListener 'change', @handleChange
  render: ->
    profile = @props.store.getCurrentProfile()
    status = @props.store.getStatus()
    d.div {className: 'outer-container'}, d.div {className: 'inner-container'},
      d.div {className: 'discover'},
        if status == 'loading'
          d.div {className: 'loading'}, d.span {}, $l('loading')
        else if status == 'empty'
          d.div {className: 'empty'}, d.span {}, $l('emptyDiscover')
        d.div {className: 'photos'},
          d.div {className: 'current'},
            d.div {className: 'photo', style: backgroundImage: "url(#{profile?.primaryPhoto?.cdnBaseUrl}#{profile?.primaryPhoto?.urls?['300x300']})"},
              d.div {className: 'overlay-container'},
                d.Button {className: "view-profile square", onClick: @handleViewProfile},
                  d.Glyph(glyph: 'info')
                d.Button {className: "send-message square", onClick: @handleSendMessage},
                  d.Glyph(glyph: 'comment')
        d.div {className: 'buttons-container'},
          d.div {className: 'buttons'},
            d.Button {className: "hide-profile square", onClick: => @props.store.hide(); return},
              d.Glyph(glyph: 'remove')
            d.Button {className: "like-profile square", onClick: => @props.store.like(); return},
              d.Glyph(glyph: 'star')
