_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
moment = require('moment')
$l = require('./locale')

exports.Inbox = createFactory
  getDefaultProps: -> {
    store: new stores.InboxStore()
  }
  handleChange: -> @forceUpdate()
  componentDidMount: ->
    @props.store.on 'change', @handleChange
    @props.store.setRestClient(@props.restClient)
    @props.store.init()
  componentWillUnmount: -> @props.store.removeListener 'change', @handleChange
  handleResize: -> @forceUpdate()
  handleClick: (e) ->
    conv = @props.store.getItem(e.itemIndex)
    if d.isWithin(e.itemX, e.itemY, @trashIconStyle)
      if confirm($l("deleteMessageConfirmation").replace(/username/, conv.fromProfile.username))
        @props.store.delete(conv.fromProfileGuid)
      return
    return @props.onChangePath("/conversation/#{conv.fromProfileGuid}")
    return unless conv?.removed == false
  renderConversation: (index, scrollTop, containerSize, canvas) ->
    @props.store.setScrollTop(scrollTop)
    height = 100
    width = containerSize.width
    @trashIconStyle = {fontSize: 24, left: width-35, top: 38, height: 40, width: 35}
    renderText = (text, fontSize, width, height, style) ->
      ff = canvas.FontFace('Avenir Next Condensed, Helvetica, sans-serif', null, {weight: style?.fontWeight || 400})
      dims = canvas.measureText(text, width, ff, 16, height)
      style = _.merge {}, style, {
        top: 0
        left: 0
        fontFace: ff
        fontSize: fontSize
        width: dims.width
        height: dims.height
        lineHeight: dims.height
      }
      canvas.Text({style: style},dims.lines[0].text)

    renderConversation = (conv) =>
      return renderText("Loading...") unless conv?.fromProfile?
      upgradeToRead = @props.features.billing?.available and !@props.features.messaging?.available
      profile = conv.fromProfile
      if profile.primaryPhoto?
        url = "#{profile.primaryPhoto?.cdnBaseUrl}#{profile.primaryPhoto?.urls?['100x100']}"
      else
        url = $l("genericPhotos.#{profile.gender}")
      text = conv.text
      text = $l("messaging.upgradeToRead") if upgradeToRead
      return canvas.Group {style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'white'}},
        canvas.Image({
          style: {top: 0, left: 0, width:100, height:99}
          src: url
        })
        renderText(profile.username, 16, 600, 100, {translateY: 10, translateX: 110, color:'grey', fontWeight: 700})
        renderText(text.replace(/\n/,''), 16, 600, 100, {translateY: 50, translateX: 110, color:'grey'})
        if conv.deleted
          canvas.Group({style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'rgba(150,150,150,.7)'}})
        else if !upgradeToRead
          d.CanvasIcon(style: @trashIconStyle, "\uf014")

    renderRemovedConversation = (conv) =>
      return renderText("Loading...") unless conv?.fromProfile?
      url = $l("genericPhotos.#{conv.fromProfile.gender}")
      return canvas.Group {style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'rgb(200,200,200)'}},
        canvas.Image({
          style: {top: 0, left: 0, width:100, height:99}
          src: url
        })
        renderText(conv.fromProfile.username, 16, 600, 100, {translateY: 10, translateX: 110, color:'grey', fontWeight: 700})
        renderText($l("removedProfile"), 16, 600, 100, {translateY: 50, translateX: 110, color:'grey'})
        if conv.deleted
          canvas.Group({style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'rgba(150,150,150,.7)'}})
        else
          d.CanvasIcon(style: @trashIconStyle, "\uf014")

    conv = @props.store.getItem(index)
    canvas.Group({style: {left: 0, top: 0, width: width, height: height, backgroundColor: 'black'}},
      if conv?.removed
        renderRemovedConversation(conv)
      else
        renderConversation(conv)
    )

  render: ->
    d.div {className: 'outer-container'},
      d.div {className: 'inner-container'},
        d.div {className: 'messages-container'},
          if @props.store.getLoadedCount() == 0
            if @props.store.isLoading()
              d.div({className: 'info-message'}, "Loading...")
            else
              d.div({className: 'info-message'}, $l('emptyInbox'))
          else
            d.CanvasListView(
              ref: 'listView'
              numberOfItemsGetter: => @props.store.getLoadedCount()
              itemHeightGetter: => 100
              itemGetter: @renderConversation
              onClick: @handleClick
              onResize: @handleResize
              scrollTop: @props.store.getScrollTop()
              style: {top: '0px'}
            )

exports.Conversation = createFactory
  getDefaultProps: -> {
    store: new stores.ConversationStore()
  }
  handleChange: -> @forceUpdate()
  handleViewProfile: (e) ->
    e.preventDefault()
    @props.onChangePath("/profile/#{@props.conversation.conversationWithGuid}")
  componentWillMount: ->
    @props.store.init(@props.conversation)
    conv = @props.store.getConversation(@props.conversation.conversationWithGuid)
    @setState(loadedMessages: conv?.messages?.length)
  componentDidMount: ->
    @props.store.on 'change', @handleChange
    @props.store.setRestClient(@props.restClient)
  componentWillUnmount: -> @props.store.removeListener 'change', @handleChange
  componentDidUpdate: ->
    if (@shouldScrollBottom)
      node = $('body')[0]
      node.scrollTop = node.scrollHeight
  render: ->
    conv = @props.store.getConversation(@props.conversation.conversationWithGuid)
    profile = conv.profileSummary
    unless profile?
      return d.div {className: 'outer-container'}, d.div {className: 'inner-container', style: paddingTop: 20}, d.h2 {}, $l('removedProfile')
    if profile.primaryPhoto?
      url = "#{profile.primaryPhoto?.cdnBaseUrl}#{profile.primaryPhoto?.urls?['100x100']}"
    else
      url = $l("genericPhotos.#{profile.gender}")
    previousMessage = null
    messages = conv.messages
    unless @state?.showAllMessages
      removedMessages = (@state?.loadedMessages || messages.length) - 3
      messages = _.takeRight(messages, messages.length - removedMessages)
    d.div {className: 'outer-container conversation'},
      d.div {className: 'inner-container'},
        d.a {onClick: @handleViewProfile},
          d.div({className: 'profile-summary'},
            d.div {className: "photo #{@props.className}"}, d.img {width: '100%', height: '100%', src: url}
            d.div {className: "username"}, profile.username
            d.div {className: "info"},
              d.span {}, profile.age
              d.Bullet({})
              d.span {}, profile.city || "United States"
          )
        d.div {className: 'messages'},
          if removedMessages? and removedMessages > 0
            d.Button {className: "see-all-messages", onClick: => @setState(showAllMessages:true)}, "See #{removedMessages} older messages"
          _.map(messages, (message) =>
            previousType = previousMessage?.type
            previousMessage = message
            d.div {className: "message #{message.type} #{previousType}-#{message.type}"},
              if message.type=='received'
                d.div {className: "photo"},
                  d.a {onClick: @handleViewProfile},
                    d.img {width: '100%', height: '100%', src: url}
              d.div {className: "text"}, message.text
              d.div {className: "timestamp"}, moment.utc(message.timestamp).from(moment())
          )...
        d.div {className: "send-message"},
          d.textarea {
            placeholder: $l('messaging.sendMessagePlaceholder')
            ref: 'messageText'
            value: @state?.message
            onChange: (e) => @setState(message: $(e.target).val())
          }
          d.Button {
            className: "pill send tiny"
            onClick: =>
              @props.store.sendMessage conv.conversationWithGuid, @state.message, =>
                @shouldScrollBottom = true
                @setState(message: "")
          }, "Send"