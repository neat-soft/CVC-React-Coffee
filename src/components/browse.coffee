_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
$l = require('./locale')

BrowseFilter = createFactory
  handleFilterChange: (e) ->
    @props.handleFilterChange(e.target.name, e.target.value)
  render: ->
    genders = [
      {value: 'M', label: 'Men'}
      {value: 'F', label: 'Women'}
    ]
    ages = _.map [18..99], (age) -> {value: age.toString(), label: age}
    distance = _.map [100, 200, 300, 500, 2000], (d) -> {value: d.toString(), label: "#{d} mi"}
    d.div {className: 'filters'}, [
      d.SelectField {label: 'Show me', options:genders, name: 'gender', defaultValue: @props.filter?.gender, onChange: @handleFilterChange}
      d.SelectField {label: 'Looking for', options:genders, name: 'lookingFor[gender]', defaultValue: @props.filter?.lookingFor?.gender, onChange: @handleFilterChange}
      d.SelectField {label: 'Between', options:ages, name: 'minAge', defaultValue: @props.filter?.minAge, onChange: @handleFilterChange}
      d.SelectField {label: 'and', options:ages, name: 'maxAge', defaultValue: @props.filter?.maxAge, onChange: @handleFilterChange}
      #d.SelectField {label: 'Within', options:distance, name: 'maxDistance', defaultValue: @props.filter?.maxDistance || "2000", onChange: @handleFilterChange}
    ]...

ProfileSearchResults = createFactory
  renderItem: (itemIndex, scrollTop, itemSize, canvas) ->
    profile = @props.store.getProfile(itemIndex)
    ff = canvas.FontFace('Open Sans, Helvetica, sans-serif', null, {weight: 700})
    dims = canvas.measureText("Loading...", itemSize, ff, 16, 30)
    style =
      top: itemSize / 2 - dims.height / 2
      left: itemSize / 2 - dims.width / 2
      fontFace: ff
      fontSize: 16
      width: dims.width
      height: dims.height
      lineHeight: dims.height
      color:'grey'
      backgroundColor: 'white'

    if profile?
      ageAndLocation = "#{profile.age}"
      if profile?.profileLocation?.city?
        ageAndLocation = "#{ageAndLocation} from #{profile.profileLocation.city}, #{profile.profileLocation.stateCode}"
      url = "#{profile.primaryPhoto?.cdnBaseUrl}#{profile.primaryPhoto?.urls?['300x300']}"
      canvas.Group({style: {left: 0, top: 0, width: itemSize, height: itemSize, backgroundColor: 'white'}},
        canvas.Text({style: style},"Loading...")
        canvas.Image({
          style: {top: 0, left: 0, width:itemSize - 1, height:itemSize - 1, borderWidth: 0, borderColor: 'white'}
          src: url
        })
        canvas.Group({style: {left: 0, top: 0, width: itemSize-2, height: 30, backgroundColor: 'rgba(100,100,100,.8)'}},
          canvas.Text({style: {top: 5, left: 5, width: itemSize-11, height: 20, lineHeight: 20, fontSize: 18, fontFace: ff, color:'white'}},"#{ageAndLocation}")
          #d.CanvasIcon({style: {fontSize: 18, right: itemSize-9, top: 4, color: 'white'}}, "\uf024")
          #d.CanvasIcon({style: {fontSize: 34, right: itemSize-4, top: -5, color: 'white'}}, "\uf096")
        )
      )
    else if @props.store.isLoading() == true
      canvas.Group({style: {left: 0, top: 0, width: itemSize, height: itemSize, backgroundColor: 'white'}},
        canvas.Text({style: style},"Loading...")
      )

  handleClick: (itemIndex, e) ->
    profile = @props.store.getProfile(itemIndex)
    if profile?
      if e.itemX > e.itemWidth - 30 and e.itemY < 30
        @handleFlag(itemIndex, e)
      else
        @props.onClick(profile) if @props.onClick?

  handleFlag: (itemIndex, e) -> console.log "FLAG", itemIndex

  render: ->
    if @props.store.getLoadedCount() == 0
      if @props.store.isLoading()
        return d.div({className: 'info-message'}, "Loading...")
      else
        return d.div({className: 'info-message'}, $l('notEnoughUsers'))
    d.CanvasGridView(
      ref: 'listView'
      style:
        top: '120px'
      numberOfItems: @props.store.getLoadedCount() || 0
      itemSize: 300
      itemMinSize: 200
      renderItem: @renderItem
      onClick: @handleClick
      scrollTop: @props.store.getScrollTop()
      onScroll: @props.store.setScrollTop.bind(@props.store)
    )

module.exports = createFactory
  propTypes:
    defaultFilter: React.PropTypes.object.isRequired
  getDefaultProps: -> {
    store: new stores.BrowseStore()
  }
  handleClick: (profile) ->
    @props.onChangePath("/profile/#{profile.guid}")

  handleChange: -> @forceUpdate()
  componentWillMount: ->
    @props.store.preload(@props.items, @props.totalFound)
    @props.store.init(@props.defaultFilter)
  componentDidMount: ->
    @props.store.on 'change', @handleChange
    @props.store.setRestClient(@props.restClient)
  componentWillUnmount: -> @props.store.removeListener 'change', @handleChange

  handleSearch: ->
    @props.store.search()

  render: ->
    d.div {className: 'browse'},
      BrowseFilter filter: @props.store.getFilter(), handleFilterChange: @props.store.handleFilterChange.bind(@props.store)
      ProfileSearchResults(
        ref: 'results'
        store: @props.store
        onClick: @handleClick
      )
