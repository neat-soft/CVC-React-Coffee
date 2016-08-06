_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
stores = require('./stores')
{Photo, PhotoPlaceholder} = require('./profile')
$l = require('./locale')

UploadPrimaryPhoto = createFactory
  handlePickPhoto: -> @refs.fileUploader.pickFile()
  render: ->
    d.div {className: 'upload-photo'}, [
      d.FileUploader({ref: 'fileUploader', name: 'photo', accept: 'image/*', onProgress: @props.onProgress, onComplete: @props.onComplete, parameters: {continueTo: @props.continueTo}})
      PhotoPlaceholder {className: 'primary', gender: @props.gender, message: 'Pick your photo', onClick: @handlePickPhoto},
        d.a {className: 'link-overlay', href: '#', }
    ]...

PhotoSummary = createFactory
  render: ->
    d.div {className: "photo-summary #{if @props.children.album=='primary' then 'primary'}"}, [
      if @props.children.storage == 'pending'
        PhotoPlaceholder {gender: @props.gender, message: 'Pending'}
      else
        Photo {dims: '100x100'}, @props.children
      d.div {className: 'buttons'}, [
        d.Button {className: 'square delete', href: '#', onClick: @props.onDelete.bind(null, @props.children.guid)}, "Delete"
        unless @props.children.album == 'primary'
          d.Button {className: 'square primary', href: '#', onClick: @props.onMakePrimary.bind(null, @props.children.guid)}, "Make Primary"
      ]...
    ]...

PhotoList = createFactory
  render: ->
    d.div {className: 'list'}, _.map(@props.store.getPhotos(), (photo) =>
      PhotoSummary({onDelete: @props.onDelete, onMakePrimary: @props.onMakePrimary, gender: @props.gender}, photo)
    )...

module.exports = createFactory
  getDefaultProps: -> {
    store: new stores.PhotosStore()
  }
  handleContinue: -> @props.onChangePath(@props.continueTo)
  handleUploadPhoto: (e) -> @refs.fileUploader.pickFile()
  handleDelete: (guid, e) -> @props.store.delete(guid)
  handleMakePrimary: (guid, e) -> @props.store.makePrimary(guid)
  handleChange: -> @forceUpdate()
  componentWillMount: -> @props.store.init(@props.photos)
  componentDidMount: ->
    @props.store.on 'change', @handleChange
    @props.store.setRestClient(@props.restClient)
  componentWillUnmount: -> @props.store.removeListener 'change', @handleChange
  handleProgress: (progress) ->
    @refs.progressBar.show("#{Math.round(progress)}%", progress)
  handleComplete: (success, result) ->
    if success
      @setState(message: $l('photos.uploadOk'), error: false)
    else
      @setState(message: $l('photos.uploadFailed'), error: true)
    @refs.dialog.show(false, false)
    @refs.progressBar.hide()
  handleDialogClose: ->
    @refs.dialog.hide()
    return if @state.error
    @props.store.refresh()
    return @props.onChangePath(@props.continueTo, true) if @props.continueTo?
  render: ->
    d.div {className: 'outer-container'}, d.div {className: 'inner-container'},
      d.ModalDialog {ref: 'dialog', className: 'dialog'},
        d.div {className: 'message'}, @state?.message
        d.div {className: 'buttons'}, d.Button {className: 'close', onClick: @handleDialogClose}, "Close"
      d.ProgressBar {ref: 'progressBar'}
      d.div {className: 'manage-photos'}, _.flatten([
        unless @props.store.getPhotos().length > 0
          UploadPrimaryPhoto({gender: @props.myProfileSummary?.gender, continueTo: @props.continueTo, onProgress: @handleProgress, onComplete: @handleComplete})
        else
          [ d.div {className: 'buttons'}, [
              d.Button {className: 'square upload-photo', onClick: @handleUploadPhoto}, "Upload More Photos"
              d.FileUploader({ref: 'fileUploader', name: 'photo', accept: 'image/*', onProgress: @handleProgress, onComplete: @handleComplete, parameters: {continueTo: @props.continueTo}})
            ]...
            PhotoList(store: @props.store, onDelete:@handleDelete, onMakePrimary: @handleMakePrimary, gender: @props.myProfileSummary.gender)
          ]
        if @props.continueTo?
          d.div {className: 'buttons'},
            d.Button {className: 'square', onClick: @handleContinue}, "Continue"
      ])...
