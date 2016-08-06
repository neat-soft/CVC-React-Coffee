_ = require('lodash')
React = require('react')
ReactCanvas = null
dom = React.DOM
common = require('./common')

canvasFactories = {
  renderText: (text, fontSize, width, height, style) ->
    ff = @FontFace('Avenir Next Condensed, Helvetica, sans-serif', null, {weight: style?.fontWeight || 400})
    dims = @measureText(text, width, ff, fontSize, height)

    style = _.merge {}, {
      top: 0
      left: if style.textAlign == 'center' then width / 2 - dims.width / 2  else 0
      fontFace: ff
      fontSize: fontSize
      width: dims.width
      height: dims.height
      lineHeight: dims.height
    }, style
    @Text({style: style},dims.lines[0].text)
}

exports.isWithin = (x, y, dims) ->
  dims.left < x and (dims.left + dims.width) > x and dims.top < y and (dims.height + dims.top) > y

exports.CanvasIcon = common.createFactory
  componentWillMount: ->
    @iconsFontFace = ReactCanvas.FontFace('FontAwesome', null, {weight: 'normal'})
    @dims = ReactCanvas.measureText(@props.children, 10000, @iconsFontFace, @props.style.fontSize, @props.style.height || @props.style.fontSize) #we don't care about max width because its just one character

  render: ->
    style = _.merge {
      fontFace: @iconsFontFace
      left: (@props.style.right - @dims.width) if @props.style.right?
      top: (@props.style.bottom - @dims.height) if @props.style.bottom?
      height: @dims.height
      width: @dims.width
      lineHeight: @dims.height
      textAlign: 'center'
    }, @props.style
    canvasFactories.Text(style: style,@props.children)

exports.CanvasListView = common.createFactory
  componentDidMount: ->
    unless ReactCanvas?
      ReactCanvas = require('react-canvas')
      notElements = ['measureText', 'FontFace']
      for own component, def of ReactCanvas
        if component in notElements
          canvasFactories[component] = def
        else
          canvasFactories[component] = React.createFactory(def)
    $('html').addClass('no-scroll')
    @setState(size: @getContainerBoundingRect())
    @forceUpdate()
    $(window).on 'keydown', @handleKeyPress
    $(window).on 'resize', @handleWindowResize
    $(window).on 'wheel', @handleWheel

  componentWillUnmount: ->
    $(window).off 'keydown', @handleKeyPress
    $(window).off 'resize', @handleWindowResize
    $(window).off 'wheel', @handleWheel
    $('html').removeClass('no-scroll')

  handleKeyPress: (e) ->
    return unless @refs.listView?
    pageSize = @refs.listView.scroller.__clientHeight
    totalSize = @refs.listView.scroller.getScrollMax().top
    smallScroll = Math.max(150, @calculateItemHeight() / 2)
    scrollByMap = {
      40: smallScroll
      38: -smallScroll
      34: pageSize
      33: -pageSize
      35: totalSize
      36: -totalSize
    }
    scrollBy = scrollByMap[e.keyCode]
    return unless scrollBy?
    @scrollBy(scrollBy)

  handleWindowResize: ->
    @updateScrollingDimensions()
    @setState(size: @getContainerBoundingRect())
    @props.onResize() if @props.onResize?
    @forceUpdate()

  handleWheel: (e) ->
    deltaY = e.originalEvent?.deltaY || e.deltaY
    smallScroll = Math.max(150, @calculateItemHeight() / 2)
    smallScroll*= -1 if deltaY < 0
    @scrollBy(smallScroll)

  scrollBy: (scrollBy) ->
    return unless @refs.listView?
    scrollMax = @refs.listView.scroller.getScrollMax().top
    scrollTop = @refs.listView.state?.scrollTop || 0
    scrollTop+= scrollBy
    scrollTop = 0 if scrollTop < 0
    scrollTop = scrollMax if scrollTop > scrollMax
    @refs.listView.scrollTo(0, scrollTop, false)

  handleClick: (e) ->
    size = @getContainerBoundingRect()
    itemHeight = @calculateItemHeight()
    actualY = e.clientY + @refs.listView.state.scrollTop - size.top
    e.itemIndex = Math.ceil(actualY / itemHeight) - 1
    e.itemX = e.clientX - size.left
    e.itemY = actualY - (itemHeight * e.itemIndex)
    e.containerSize = size
    e.itemHeight = itemHeight
    @props.onClick(e) if @props.onClick?

  updateScrollingDimensions: ->
    if @refs.listView?
      @refs.listView.updateScrollingDimensions()
      @__cachedItemHeight = null

  resetScroll: ->
    @refs.listView.scrollTo(0, 0, false) if @refs.listView?

  componentWillReceiveProps: (nextProps) ->
    @updateScrollingDimensions()

  render: ->
    style = {
      position: 'absolute'
      bottom: '0px'
      top: '0px'
      width: '100%'
      overflow: 'hidden'
      cursor: 'pointer'
    }
    emptyContainer = dom.div {ref: 'container', className: @props.className, style: _.merge(style, @props.style)}
    return emptyContainer unless ReactCanvas?
    return emptyContainer unless @state?.size?
    size = @state.size
    dom.div {id:@props.id, ref: 'container', className: @props.className, style: _.merge(style, @props.style), onClick: @handleClick},
      canvasFactories.Surface {top: 0, left: 0, width: size.width, height: size.height},
        canvasFactories.ListView(
          ref: 'listView'
          style: {top: 0, left: 0, width: size.width, height: size.height}
          numberOfItemsGetter: @calculateNumberOfItems
          itemHeightGetter: @calculateItemHeight
          itemGetter: @renderItem
          onScroll: @props.onScroll
          scrollTop: @props.scrollTop
        )

  getContainerBoundingRect: -> @refs.container.getDOMNode().getBoundingClientRect();

  renderItem: (itemIndex, scrollTop)->
    size = @state.size
    @props.itemGetter(itemIndex, scrollTop, size, canvasFactories)

  calculateItemHeight: ->
    return @__cachedItemHeight if @__cachedItemHeight?
    size = @state.size
    @__cachedItemHeight = @props.itemHeightGetter(size)

  calculateNumberOfItems: ->
    size = @state.size
    @props.numberOfItemsGetter(size)

exports.CanvasGridView = common.createFactory
  propTypes:
    numberOfItems: React.PropTypes.number.isRequired
    itemSize: React.PropTypes.number.isRequired
    #renderItem: React.PropTypes.function.isRequired

  renderLine: (lineIndex, scrollTop, containerSize, canvas) ->
    itemSize = @calculateItemSize(containerSize)
    itemsPerLine = containerSize.width / itemSize
    line = [(lineIndex)*itemsPerLine..(lineIndex+1)*itemsPerLine]
    return canvas.Group {style:{top: 0, left: 0, width:itemSize*itemsPerLine, height:itemSize}}, _.flatten(
      _.map line, (itemIndex, index) =>
        item = @props.renderItem(itemIndex, scrollTop, itemSize, canvas)
        canvas.Group({style: {left: 0, top: 0, width: itemSize, height: itemSize, translateX: index*itemSize}}, item)
    )...

  handleClick: (e) ->
    e.preventDefault()
    itemSize = @calculateItemSize(e.containerSize)
    column = Math.ceil(e.itemX / itemSize) - 1
    itemsPerLine = e.containerSize.width / itemSize
    item = itemsPerLine * e.itemIndex + column
    e.itemX = e.itemX % itemSize
    e.itemWidth = e.itemHeight
    @props.onClick(item, e) if @props.onClick?

  componentWillUpdate: ->
    @refs.listView.updateScrollingDimensions()
    @_itemSizeCache = null

  handleResize: ->
    @_itemSizeCache = null
    @forceUpdate()

  calculateItemSize: (containerSize) ->
    return @_itemSizeCache if @_itemSizeCache?
    itemMinSize = @props.itemMinSize || @props.itemSize
    @_itemSizeCache = if containerSize.width > @props.itemSize
      itemsPerLine = Math.round(containerSize.width / @props.itemSize)
      containerSize.width / itemsPerLine
    else if containerSize.width <= itemMinSize
      containerSize.width
    else
      itemsPerLine = Math.round(containerSize.width / itemMinSize)
      containerSize.width / itemsPerLine

  calculateNumberOfLines: (containerSize) ->
    itemsPerLine = containerSize.width / @calculateItemSize(containerSize)
    lines = Math.ceil(@props.numberOfItems / itemsPerLine)
    lines

  getScrollTop: ->
    @refs.listView.getScrollTop()

  resetScroll: ->
    @refs.listView.resetScroll()

  render: ->
    exports.CanvasListView(
      ref: 'listView'
      numberOfItemsGetter: @calculateNumberOfLines
      itemHeightGetter: @calculateItemSize
      itemGetter: @renderLine
      onClick: @handleClick
      onResize: @handleResize
      scrollTop: @props.scrollTop
      style: @props.style
      onScroll: @props.onScroll
    )
