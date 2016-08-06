_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
$l = require('./locale')

ages = _.object _.map [18..99], (age) -> [age, age]

exports.PhotoPlaceholder = PhotoPlaceholder = createFactory
  propTypes:
    gender: React.PropTypes.string.isRequired
    message: React.PropTypes.string

  render: ->
    genderMap = {M: 'male', 'F': 'female'}
    Photo {className: "photo-generic #{genderMap[@props.gender]} #{@props.className}", message: @props.message, onClick: @props.onClick}, @props.children

exports.Photo = Photo = createFactory
  handleClick: (e) ->
    e.preventDefault()
    @props.onClick(e) if @props.onClick?
  render: ->
    photo = _.flatten([@props.children])[0]
    url = photo?.urls?[@props.dims]
    url = "#{photo?.cdnBaseUrl}#{url}" if url?
    d.div {className: "photo #{@props.className}"},
      d.div {className: 'loading'}, d.span {}, "Loading..." unless @props.message?
      d.img {width: '100%', height: '100%', src: url}
      d.div {className: "message"}, @props.message if @props.message?
      d.a {className: 'link-overlay', href: '#', onClick: @handleClick} if @props.onClick

EditLabel = createFactory
  render: ->
    d.div {className: 'edit-label'},
      d.h3 {}, @props.children if @props.children?
      d.Button {className: 'tiny edit square uppercase', onClick: @props.onEdit}, 'Edit' if not @props.editMode is true
      d.Button {className: 'tiny save square uppercase', onClick: @props.onSave}, 'Save' if @props.editMode is true
      d.Button {className: 'tiny cancel square uppercase', onClick: @props.onCancel}, 'Cancel' if @props.editMode is true

EditableSection = (focusProps) -> (Component) -> createFactory
  #getInitialState: -> {editMode: true}
  handleEdit: ->
    @setState(editMode: true)
    focusProps.focusOn(@refs.section.getDOMNode()) if focusProps.focusOn?
  handleCancel: ->
    @setState(editMode: false)
    focusProps.unfocus() if focusProps.unfocus?
  handleSave: ->
    @setState(editMode: false)
    @props.onChange(@refs.component.value()) if @props.onChange?
    focusProps.unfocus() if focusProps.unfocus?
  componentDidMount: ->
    $(@refs.section.getDOMNode()).resize =>
      focusProps.onResize() if focusProps.onResize?
  render: ->
    d.div {ref: 'section', className: "#{@props.className} #{if @state?.editMode then 'edit-mode' else ''}"},
      EditLabel {onEdit: @props.onEdit || @handleEdit, editMode: @state?.editMode, onCancel: @handleCancel, onSave: @handleSave}, @props.label
      Component _.defaults({ref: 'component', editMode: @state?.editMode, editable: true}, @props), @props.children

Section = (Component) -> createFactory
  render: ->
    d.div {className: @props.className},
      d.h3 {}, @props.label if @props.label
      Component _.defaults({ref: 'component'}, @props), @props.children

AdvancedCriteriaTable = createFactory
  value: -> _.merge {}, @props.children, @state
  handleChange: (field, e) ->
    value = $(@refs[field].getDOMNode()).val()
    @setState(_.object [[field, value]])
  render: ->
    d.div({},
      _.map(@props.children, (v, k) =>
        v = @state[k] if @state?[k]?
        rendered =
          label: $l("advancedCriteria.#{k}")
          value: $l("options.#{k}.#{v}") || v if v? and v!=''
        options = $l("options.#{k}")
        if @props.editMode
          if _.isObject(options)
            rendered.value = d.select {ref: k, value: v, onChange: @handleChange.bind(null, k)},
              d.option {}, ""
              _.map(options, (label, option) ->
                d.option {value: option}, label
              )...
          else
            rendered.value = d.input {ref: k, value: rendered.value, onChange: @handleChange.bind(null, k)}
        d.DescriptionList({label: rendered.label}, rendered.value) if (rendered.value? and rendered.value!='') or @props.editable
      )...
    )

LookingForTable = createFactory
  value: -> _.merge {}, @props.children, @state
  handleChange: (e) ->
    value = $(e.target).val()
    field = $(e.target).attr('name')
    @setState(_.object [[field, value]])
  render: ->
    if @props.editMode
      d.BulletList {}, [
        d.DropDown {name: 'gender', value: @state?.gender || @props.children.gender, onChange: @handleChange}, $l("gender_plural")
        d.span {},
          "Between "
          d.DropDown {name: 'minAge', value: @state?.minAge || @props.children.minAge, onChange: @handleChange}, ages
          " and "
          d.DropDown {name: 'maxAge', value: @state?.maxAge || @props.children.maxAge, onChange: @handleChange}, ages
        d.DropDown {name: 'distance', value: @state?.distance || @props.children.distance, onChange: @handleChange}, $l("options.distance")
        d.DropDown {name: 'relationshipType', value: @state?.relationshipType || @props.children.relationshipType, onChange: @handleChange}, $l("options.relationshipType")
      ]...
    else
      d.BulletList {}, [
        $l("gender_plural.#{@props.children.gender}")
        d.span {}, ["Between ", d.span({}, @props.children.minAge), " and ", d.span({}, @props.children.maxAge)]...
        $l("options.distance.#{@props.children.distance}")
        $l("options.relationshipType.#{@props.children.relationshipType}")
      ]...

ProfileContent = createFactory
  value: ->
    return @props.children unless @refs.textarea?
    @refs.textarea.value()
  render: ->
    if @props.editMode
      d.AutoGrowTextArea {ref: 'textarea', defaultValue: @props.children}
    else
      d.span {}, @props.children

Username = createFactory
  handleChange: (e) ->
    value = $(e.target).val()
    field = $(e.target).attr('name')
    @setState(_.object [[field, value]])
  value: -> @state?.username || @props.children
  render: ->
    d.h3 {className: 'username'},
      if @props.editMode
        d.input(name: 'username', value: @state?.username || @props.children, onChange: @handleChange)
      else
        @props.children

ProfileInfo = createFactory
  getDefaultProps: -> {
    store: new stores.LocationStore()
  }
  getInitialState: -> {
    postalCode: @props.children.profileLocation?.postalCode
    profileLocationGuid: @props.children.profileLocation?.guid
    profileLocation: @props.children.profileLocation
    age: @props.children.age
    gender: @props.children.gender
  }
  handleChange: (e) ->
    value = $(e.target).val()
    field = $(e.target).attr('name')
    @setState(_.object [[field, value]])
  value: -> _.omit(@state, 'postalCode', 'locations')
  handlePostalChange: (value) ->
    @props.store.updateLocations(value)
    @setState(postalCode: value)
  handleStoreChange: ->
    locations = @props.store.getLocations()
    @setState(profileLocation: locations[0])
    @setState(profileLocationGuid: locations[0]?.guid) unless @props.store.getLocation(@state.profileLocationGuid)
    @forceUpdate()
  componentDidMount: ->
    @props.store.setRestClient(@props.restClient)
    @props.store.on 'change', @handleStoreChange
    if @props.editable
      @props.store.preload([@props.children.profileLocation])
      @handlePostalChange(@state.postalCode)
  componentWillUnmount: ->
    @props.store.removeListener 'change', @handleStoreChange
  handleCityChange: (e) ->
    @setState(
      profileLocationGuid: $(e.target).val()
      profileLocation: @props.store.getLocation($(e.target).val())
    )
  render: ->
    d.div {className: 'info', ref: 'info'},
      (if @props.editMode
        [ d.DropDown {name: 'age', value: @state?.age || @props.children.age, onChange: @handleChange}, ages
          d.DropDown {name: 'gender', value: @state?.gender || @props.children.gender, onChange: @handleChange}, $l("gender")
          d.div {className: 'location'},
            d.div {className: 'location-field'},
              d.label {}, $l('location.postalCode')
              d.input {defaultValue: @state.postalCode, onChange: (e) => (@handlePostalChange($(e.target).val()))}
            d.div {className: 'location-field'},
              d.label {}, $l('location.city')
              d.select {defaultValue: @state.profileLocationGuid, onChange: @handleCityChange},
                _.map(@props.store.getLocations(), (loc) ->
                  d.option {value: loc.guid}, "#{loc.city}, #{loc.stateCode}"
                )...
        ]
      else
        [ d.span {}, @state?.age || @props.children.age
          d.Bullet({})
          d.span {}, $l("gender.#{@state?.gender || @props.children.gender}")
          d.Bullet({})
          d.span {}, "#{@props.children.profileLocation?.city}, #{@props.children.profileLocation?.stateCode}"
        ]
      )...

PhotoWithPlaceholder = createFactory
  render: ->
    if @props.photo? and @props.photo.storage!='pending'
      Photo {className: 'primary', dims: '300x300'}, @props.photo
    else
      PhotoPlaceholder {className: 'primary', gender: @props.gender, message: (if @props.photo?.storage == 'pending' then 'Pending')}


SlidingPhotoGallery = createFactory
  getInitialState: -> {
    index: 0
  }
  getDeltaX: (e) ->
    deltaX = @startX - e.changedTouches[0].screenX
    deltaX = 0 if deltaX < 0 and @state.index == 0
    deltaX = 0 if deltaX > 0 and @state.index == @props.photos.length-1
    deltaX

  handleTouchMove: (e) ->
    deltaX = @getDeltaX(e)
    $(@refs.current.getDOMNode()).css(left: -deltaX)
    $(@refs.next.getDOMNode()).css(left: @containerWidth-deltaX) if @refs.next?
    $(@refs.previous.getDOMNode()).css(left: -@containerWidth-deltaX) if @refs.previous?
  handleTouchStart: (e) ->
    @containerWidth = $(@refs.current.getDOMNode()).innerWidth()
    @startX = e.changedTouches[0].screenX
  handleTouchEnd: (e) ->
    deltaX = @getDeltaX(e)
    if deltaX > (@containerWidth/3)
      @setState(index: @state.index+1)
    else if deltaX < -(@containerWidth/3)
      @setState(index: @state.index-1)
    $(@refs.current.getDOMNode()).css(left: 0)
    $(@refs.next.getDOMNode()).css(left: 0) if @refs.next?
    $(@refs.previous.getDOMNode()).css(left: 0) if @refs.previous?
  handleClick: (e) ->
    e.preventDefault()
    return if $(@refs.current.getDOMNode()).innerWidth() != 300
    @props.onClick(e) if @props.onClick?

  render: ->
    d.div {ref: 'container', className: 'sliding-gallery', onClick: @handleClick, onTouchStart: @handleTouchStart, onTouchEnd: @handleTouchEnd, onTouchMove: @handleTouchMove},
      d.div({ref: 'previous', className: 'previous'}, PhotoWithPlaceholder {photo: @props.photos[@state.index-1], gender: @props.gender}) if @props.photos[@state.index-1]?
      d.div({ref: 'current', className: 'current'}, PhotoWithPlaceholder {photo: @props.photos[@state.index], gender: @props.gender})
      d.div({ref: 'next', className: 'next'}, PhotoWithPlaceholder {photo: @props.photos[@state.index+1], gender: @props.gender}) if @props.photos[@state.index+1]?

PopupMenu = createFactory
  getInitialState: -> {
    visible: @props.visible || false
  }
  show: -> @setState(visible: true)
  hide: -> @setState(visible: false)
  handleItemClick: (item, e) ->
    e.preventDefault()
    @hide()
    @props.onClick(item , e) if @props.onClick?
  render: ->
    console.log @props
    d.div {className: "popup-menu-container #{if @state.visible then 'visible' else 'hidden'}", onClick: @hide},
      d.span {className: 'align-helper'}
      d.div {className: 'popup-menu'}, _.map(@props.items, (item) =>
        d.a {href: '#', onClick: @handleItemClick.bind(null, item)}, $l("popupMenu.#{item}")
      )...

exports.Profile = createFactory
  getDefaultProps: -> {
    store: new stores.ProfileStore()
  }
  getInitialState: -> {
  }
  componentWillReceiveProps: (nextProps)-> @props.store.preload(nextProps.profile)
  componentWillMount: -> @props.store.preload(@props.profile)
  componentDidMount: ->
    @props.store.setRestClient(@props.restClient)
    @props.store.on 'change', => @forceUpdate()
  handleChange: (section, values) ->
    updates = _.object [[section, values]]
    @props.restClient.post '', updates
    @setState(updates)
  handleChangeContent: (section, values) ->
    updates = _.object [[section, values]]
    @props.restClient.post '', content: updates
    @setState(_.object [["content_#{section}", values]])
  handleProfileInfoChange: (profileInfo) ->
    @props.restClient.post '', profileInfo
    @setState(profileInfo)
  handleLikeProfile: ->
    @props.store.flipLikeFlag()
  handleHideProfile: ->
    @props.store.hide()
  handleReportProfile: ->
    @refs.reportOptions.show()
  handleSendMessage: ->
    profile = @props.store.getState()
    @props.onChangePath("/conversation/#{profile.guid}")
  handleShowMoreOptions: (e) ->
    @refs.moreOptions.show()
  handleOptionClick: (choice, e) ->
    if choice == 'message'
      @handleSendMessage()
    else if choice == 'like'
      @handleLikeProfile()
    else if choice == 'hide'
      @handleHideProfile()
    else if choice == 'report'
      @handleReportProfile()
  handleReportOption: (choice) ->
    @props.store.report(choice)
  render: ->
    profile = @props.store.getState()
    unless profile?
      return d.div {className: 'outer-container'}, d.div {className: 'inner-container', style: paddingTop: 20}, d.h2 {}, $l('removedProfile')
    section = if @props.editable
      EditableSection(
        focusOn: (element) => @refs.focusSection.focus(element)
        unfocus: => @refs.focusSection.unfocus()
        onResize: => @refs.focusSection.handleWindowResize()
      )
    else
      Section

    d.div {className: 'outer-container'}, d.div {className: 'inner-container'},
      d.FocusSection {ref: 'focusSection', animate: true}
      PopupMenu {ref: 'moreOptions', items: ['message', 'like', 'hide', 'report'], onClick: @handleOptionClick}
      PopupMenu {ref: 'reportOptions', items: ['fake', 'scammer', 'badPhoto', 'offensive', 'other', 'cancel'], onClick: @handleReportOption}
      d.div {className: 'profile'}, [
        d.div {className: 'photos-and-info'}, [
          d.div {className: 'photos'}, [
            SlidingPhotoGallery({gender: profile.gender, onClick: (=> @setState(zoomPhotoIndex: 0)), photos: _.filter(_.flatten([profile.primaryPhoto, profile.photos]), (p) -> p?)})
            _.map(profile.photos, (photo, index) =>
              if photo.storage!='pending'
                Photo {className: 'other', dims: '300x300', onClick: => @setState(zoomPhotoIndex: index+1)}, photo
              else
                PhotoPlaceholder {className: 'other', gender: profile.gender, message: (if photo.storage == 'pending' then 'Pending')}
            )...
          ]...
          Section(Username) {className: 'username-container'}, profile.username
          section(ProfileInfo) {className: 'profile-info-container', onChange: @handleProfileInfoChange, restClient: @props.rootRestClient}, _.pick(_.defaults({}, @state || {}, profile), 'age', 'gender', 'city', 'profileLocation')
          (if @props.editable!=true
            [ d.Button {className: 'send-message square', onClick: @handleSendMessage},
                d.Glyph(glyph: 'comment')
                d.span {className: 'button-label'}, "Message"
              d.Button {className: "like-profile square#{if profile.flags?.liked then ' is-liked' else ''}", onClick: @handleLikeProfile},
                d.Glyph(glyph: 'star')
                d.span {className: 'button-label'}, "Like"
              d.Button {className: "more-options square", onClick: @handleShowMoreOptions},
                d.Glyph(glyph: 'ellipsis-h')
                d.span {className: 'button-label'}, "More"
            ]
          else
            [d.Button {className: 'photos-button square', onClick: => @props.onChangePath('/photos')},
              d.Glyph(glyph: 'camera')
              d.span {className: 'button-label'}, "Photos"
            ]
          )...
        ]...
        d.div {className: "content-and-details #{if (profile?.content?.length? || 0) == 0 then 'no-content' else 'has-content'}"}, [
          d.div {className: 'content'}, _.map(profile.content || [], (item) =>
            section(ProfileContent) {
              className: 'item'
              label: $l("content.#{item.type}")
              onChange: @handleChangeContent.bind(null, item.type)
            }, @state?["content_#{item.type}"] || item.content
          )...
          d.div {className: 'details'},
            section(LookingForTable) {
              className: 'looking-for'
              label: 'Looking For'
              onChange: @handleChange.bind(null, 'lookingFor')
            }, _.merge {}, profile.lookingFor, @state?.lookingFor
            section(AdvancedCriteriaTable) {
              className: 'my-details'
              label: 'My Details'
              onChange: @handleChange.bind(null, 'advancedCriteria')
            }, _.merge {}, profile.advancedCriteria, (@state?.advancedCriteria || {})
        ]...
      ]...
      if @state.zoomPhotoIndex?
        photo = if @state.zoomPhotoIndex == 0 then profile.primaryPhoto else profile.photos[@state.zoomPhotoIndex - 1]
        url = photo?.urls?['800x800']
        url = "#{photo?.cdnBaseUrl}#{url}" if url?
        d.div {className: 'photo-gallery'},
          d.span {className: 'align-helper'}
          d.div {className: 'photo-wrapper'},
            d.img {src: url}
            d.div {className: 'close'}, d.Button {onClick: => @setState(zoomPhotoIndex: null)}, $l('close')
            if @state.zoomPhotoIndex > 0
              d.div {className: 'back', onClick: => @setState(zoomPhotoIndex: @state.zoomPhotoIndex-1)},
                d.span {className: 'align-helper'}
                d.Glyph(glyph: 'chevron-left')
            if @state.zoomPhotoIndex < profile.photos?.length
              d.div {className: 'forward', onClick: => @setState(zoomPhotoIndex: @state.zoomPhotoIndex+1)},
                d.span {className: 'align-helper'}
                d.Glyph(glyph: 'chevron-right')
