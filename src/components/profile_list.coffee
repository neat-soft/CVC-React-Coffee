_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
$l = require('./locale')
moment = require('moment')

exports.ListContainer = createFactory
    handleChange: -> @forceUpdate()
    componentDidMount: ->
      @props.store.on 'change', @handleChange
    componentWillUnmount: -> @props.store.removeListener 'change', @handleChange
    handleResize: -> @forceUpdate()
    handleClick: (e) ->
      e.item = @props.store.getItem(e.itemIndex)
      @props.onClick(e) if e.item? and @props.onClick?
    getListView: -> @refs.listView
    renderItem: (index, scrollTop, containerSize, canvas) ->
      item = @props.store.getItem(index)
      return unless item?
      @props.renderItem(item, scrollTop, containerSize.width, canvas)
    render: ->
      d.div {className: 'outer-container'},
        d.div {className: 'inner-container'},
          d.div {className: 'list-container'},
            if @props.store.getLoadedCount() == 0
              if @props.store.isLoading()
                d.div({className: 'info-message'}, @props.loadingMessage)
              else
                d.div({className: 'info-message'}, @props.emptyMessage)
            else
              d.CanvasListView(
                ref: 'listView'
                numberOfItemsGetter: => @props.store.getLoadedCount()
                itemHeightGetter: => @props.itemHeight
                itemGetter: @renderItem
                onClick: @handleClick
                onResize: @handleResize
                scrollTop: @props.store.getScrollTop()
                style: {top: '0px'}
              )

exports.ProfileListContainer = createFactory
  componentDidMount: ->
    @props.store.reset() unless @props.backNavigation
    @props.store.setRestClient(@props.restClient)
    @props.store.init()
  handleLike: (profile) -> @props.store.like(profile.guid)
  handleHide: (profile) -> @props.store.hide(profile.guid)
  handleBlock: (profile) ->
    if confirm($l("blockConfirmation").replace(/username/, profile.username).replace(/pronoun/, $l("genderCapPronouns.#{profile.gender}")))
      @props.store.block(profile.guid)
  handleHide: (profile) ->
    @props.store.hide(profile.guid)
  handleClick: (e) ->
    return if e.item.blocked
    isWithin = (dims) ->
      dims.left < e.itemX and (dims.left + dims.width) > e.itemX and dims.top < e.itemY and (dims.height + dims.top) > e.itemY
    return if @state?.showOptionsFor == e.item.guid
      selectedAction = null
      _.each @actions, (dim, action) ->
        selectedAction = action if isWithin(dim)
      if selectedAction == 'message'
        @props.onChangePath("/conversation/#{e.item.guid}")
      else if selectedAction == 'hide'
        @handleHide(e.item)
      else if selectedAction == 'block'
        @handleBlock(e.item)
      @setState(showOptionsFor: null)
    else if @state?.showOptionsFor?
        @setState(showOptionsFor: null)
    else
      if isWithin(@likeButtonStyle)
        @handleLike(e.item)
      else if isWithin(@hideButtonStyle)
        @handleHide(e.item)
      else if isWithin(@moreOptionsButtonStyle)
        @setState(showOptionsFor: e.item.guid)
      else
        @props.onChangePath("/profile/#{e.item.guid}")
  renderProfile: (profile, scrollTop, width, canvas) ->
    if @props.store.getScrollTop()!=scrollTop and @state?.showOptionsFor?
      setTimeout (=> @setState(showOptionsFor: null)), 0
    @props.store.setScrollTop(scrollTop)
    height = 100
    if profile.primaryPhoto?
      url = "#{profile.primaryPhoto?.cdnBaseUrl}#{profile.primaryPhoto?.urls?['100x100']}"
    else
      url = $l("genericPhotos.#{profile.gender}")
    primaryColor = "rgb(18, 103, 112)"
    alertColor = "rgb(248, 215, 13)"
    buttonColor = "rgb(108, 79, 114)"
    buttonStyle = {backgroundColor: buttonColor, color: "white", borderWidth: 2, borderRadius: 20, height: 40, width: 40}
    selectedButtonStyle = _.defaults {backgroundColor: alertColor, color: primaryColor, borderColor: primaryColor}, buttonStyle
    location = ""
    location = "#{profile.profileLocation.city}, #{profile.profileLocation.stateCode}" if profile.profileLocation?
    @likeButtonStyle = _.defaults({fontSize: 32, left: 110, top: 50}, (if profile.liked then selectedButtonStyle else buttonStyle))
    @hideButtonStyle = _.defaults({fontSize: 32, left: 160, top: 50}, (if profile.hidden then selectedButtonStyle else buttonStyle))
    @moreOptionsButtonStyle = _.merge _.defaults({fontSize: 20, left: width-31, top: 1, backgroundColor: 'white'}, selectedButtonStyle), {height: 25, width: 30, borderRadius: 0, backgroundColor: 'white', borderColor: 'white'}

    renderButtonWithLabel = (action, position, buttonCount, label, icon) =>
      @actions ?= {}
      menuButtonStyle = {color: "white", height: 80, width: 80, top: 10, borderColor: 'white', borderRadius: 10}
      buttonSpacing = Math.min(width / buttonCount - 80, 40)
      buttonLeft = width / 2 - ((buttonSpacing + 80) * buttonCount) / 2
      left = buttonLeft + buttonSpacing / 2 + (buttonSpacing + 80) * position
      style = _.defaults({fontSize: 40, left: left}, menuButtonStyle)
      @actions[action] = style
      canvas.Group {},
        d.CanvasIcon({style: style}, icon)
        canvas.renderText(label, 16, 80, 100, {translateY: 60, translateX: left, color:'white', fontWeight: 700, textAlign: 'center'})

    timestamp = profile.reverseLikedOn || profile.lastVisitedOn
    timestamp = if timestamp? then moment(timestamp).fromNow()
    canvas.Group {style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'white'}}, _.filter([
      if !profile.viewed
        canvas.Group(style: {top: 9, left: 9, width:82, height:82, borderRadius: 41, borderWidth: 4, borderColor: 'rgb(128, 255, 0)'})
      canvas.Image({
        style: {top: 10, left: 10, width:80, height:80, borderRadius: 40, borderWidth: 2, borderColor: 'grey'}
        src: url
      })
      canvas.renderText(profile.username, 16, 600, 100, {translateY: 2, translateX: 110, color:'grey', fontWeight: 700})
      canvas.renderText(location, 16, 600, 150, {translateY: 20, translateX: 110, color:'grey', fontWeight: 700})
      if timestamp?
        canvas.renderText(timestamp, 16, 600, 150, {translateY: 72, translateX: width - 155, width: 150, textAlign: 'right', color:'grey', fontWeight: 700})
      d.CanvasIcon({style: @likeButtonStyle}, "\uf005")
      #d.CanvasIcon({style: @hideButtonStyle}, "\uf00D")
      d.CanvasIcon({style: @moreOptionsButtonStyle}, "\uf142")
      if profile.blocked or profile.hidden
        canvas.Group {style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'rgba(220,220,220,.9)'}}
      if @state?.showOptionsFor == profile.guid
        canvas.Group {style: {left: 0, top: 0, width: width, height: height-1, backgroundColor: 'rgba(120,120,120,.9)'}},
          renderButtonWithLabel("message", 0, 3, "Message", "\uf075")
          renderButtonWithLabel("hide", 1, 3, "Hide", "\uf00d")
          renderButtonWithLabel("block", 2, 3, "Block", "\uf071")
    ], (i) -> i?)...
  render: ->
    exports.ListContainer {store: @props.store, renderItem: @renderProfile, itemHeight: 100, onClick: @handleClick}


exports.LikedBy = createFactory
  getDefaultProps: -> {
    store: new stores.ProfileListStore()
  }
  render: ->
    d.ProfileListContainer @props

exports.Visitors = createFactory
  getDefaultProps: -> {
    store: new stores.ProfileListStore()
  }
  render: ->
    d.ProfileListContainer @props
