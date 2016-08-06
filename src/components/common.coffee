React = require('react')
D = React.DOM
_ = require('lodash')

defaults = {
}
createFactory = (def) -> React.createFactory(React.createClass(_.defaults({}, def, defaults)))
localCookies = undefined

module.exports = C = {
  createFactory: createFactory
  setCookies: (cookies) -> localCookies = cookies
  getCookies: -> _.clone(localCookies)

  formToObj: (form) ->
    return Object.keys(form).reduce(((output, key) ->
      parentKey = key.match(/[^\[]*/i);
      paths = key.match(/\[.*?\]/g) || [];
      paths = [parentKey[0]].concat(paths).map((key) ->
        return key.replace(/\[|\]/g, '');
      )
      currentPath = output;
      while (paths.length)
        pathKey = paths.shift();

        if (pathKey in currentPath)
          currentPath = currentPath[pathKey];
        else
          currentPath[pathKey] = if paths.length
            if isNaN(paths[0]) then {} else []
          else
            form[key]
          currentPath = currentPath[pathKey];
      return output;
    ), {});

  Button: createFactory
    getInitialState: -> {disabled: @props.disabled}
    disable: -> @setState {disabled: true}
    enable: -> @setState {disabled: false}
    handleClick: (e) ->
      if @props.onClick?
        e.preventDefault()
        @props.onClick(e) unless @state.disabled
    render: ->
      D.div {ref: 'container', className: "button #{@props.className} #{if @state.disabled then 'disabled' else ''}"},
        D.a {href: @props.href || "#", onClick: @handleClick}, @props.children

  DescriptionList: createFactory
    render: ->
      D.dl {className: @props.className},
        D.dt {}, @props.label
        D.dd {}, @props.children || @props.value

  Bullet: createFactory
    render: -> D.span {className: 'bullet'}, "•"

  BulletList: createFactory
    render: ->
      D.ul {className: @props.className}, _.map(@props.children, (child) ->
        D.li {}, child
      )...

  Glyph: createFactory
    render: ->
      D.i {className: "fa fa-#{@props.glyph} fa-fw"}

  FileUploader: createFactory
    propTypes:
      name: React.PropTypes.string.isRequired
      accept: React.PropTypes.string
      capture: React.PropTypes.bool

    pickFile: ->
      $(@refs.chooseFile.getDOMNode()).click()
    handleUploadFile: (e) ->
      e.preventDefault()
      if (navigator.userAgent.indexOf('MSIE')>=0 || navigator.appVersion.indexOf('Trident/') > 0)
        ie = true
        xhr = new ActiveXObject("Msxml2.XMLHTTP")
      else
        ie = false
        xhr = new XMLHttpRequest()
      file = e.target?.files?[0]
      return $(@refs.uploadForm.getDOMNode()).submit() unless xhr.upload and file?
      xhr.upload.addEventListener "progress", ((e) =>
        pc = parseInt(e.loaded / e.total * 100)
        @props.onProgress(pc) if @props.onProgress?
      ), false
      xhr.onreadystatechange = (e) =>
        if xhr.readyState == 4
          success = xhr.status == 200
          try
            result = JSON.parse(e.target.response)
          catch err
            success = false
            result = e.target?.response
          @props.onComplete(success, result) if @props.onComplete?
      xhr.open("POST", @props.url || document.location, true)
      if ie
        xhr.setRequestHeader("Content-Type", "multipart/form-data")
        xhr.setRequestHeader("X-File-Name", file.name)
        xhr.setRequestHeader("X-File-Size", file.size)
        xhr.setRequestHeader("X-File-Type", file.type)

      xhr.setRequestHeader('Accept', 'application/json')
      xhr.setRequestHeader('Content-Type', file.type || "image/binary")
      xhr.setRequestHeader(@props.fileNameHeader, file.name) if @props.fileNameHeader?
      xhr.setRequestHeader("local-cookies", JSON.stringify(localCookies))
      xhr.send(file)
    render: ->
      D.form {url: @props.url, method: 'post', encType: "multipart/form-data", ref: 'uploadForm', style: display: 'none'},
        _.map(@props.parameters || {}, (v, k) =>
          D.input {type: 'hidden', name: k, value: v}
        )...
        D.input _.merge {ref: 'chooseFile', type: 'file', onChange: @handleUploadFile}, @props

  AutoGrowTextArea: createFactory
    value: -> $(@refs.textarea.getDOMNode()).val()
    componentDidMount: ->
      $(@refs.textarea.getDOMNode()).autogrow(vertical: true, horizontal: false, flickering: false)
    render: ->
      D.textarea _.merge({ref: 'textarea'}, _.omit(@props, 'children')), @props.children

  DropDown: createFactory
    render: ->
      if _.isArray(@props.children)
        items = @props.children
      else
        items = _.map @props.children, (label, value) ->
          {label: label, value: value}
      D.select @props,
        (_.map items, (option) =>
          D.option {value: option.value}, option.label
        )...

  LabeledField: createFactory
    render: ->
      D.div {className: "field#{if @props.type? then ' field-'+@props.type else ''} field-#{@props.name}"}, [
        D.label {htmlFor: "field-#{@props.name}"}, @props.label || @props.placeholder
        D.div({className: "field-error-message"}, @props.errorMessage) if @props.errorMessage?
        @props.children
      ]...

  InputField: createFactory
    render: ->
      C.LabeledField @props, D.input {id: "field-#{@props.name}", name: @props.name, type: @props.type, placeholder: @props.placeholder || @props.label, value: @props.value, defaultValue: @props.defaultValue, checked: @props.checked, onChange: @props.onChange, maxLength: @props.maxLength, max: @props.max, min: @props.min}

  SelectField: createFactory
    render: ->
      C.LabeledField @props,
        D.select {name: @props.name, placeholder: @props.placeholder || @props.label, value: @props.defaultValue, onChange: @props.onChange},
          (_.map @props.options, (option) =>
            D.option {value: option.value}, option.label
          )...

  FormFieldLabel: createFactory
    render: ->
      D.label {htmlFor: @props.htmlFor}, [
        D.span {className: 'label-text'}, @props.label
        D.span {className: 'label label-danger'}, "#{@props.validationErrors[0]}" if @props.validationErrors?[0]?
      ]...

  FormFieldContainer: createFactory
    render: ->
      validationClass = if @props.validationErrors?[0]?
        'has-error'
      else if @props.value? and @props.value!=""
        'has-success'
      else
        ""
      D.div {className: "form-group #{validationClass}"}, @props.children

  FormField: createFactory
    handleChange: (e) ->
      value = $(e.target).val()
      @props.valueLink.requestChange(value)

    validateValue: (value) ->
      value?=""
      parseRegexp = (regex) ->
        return regex if regex.test?
        regex = regex.split(/^\/|\/(?=[a-z]*$)/)
        regex.shift() if regex[0]==""
        new RegExp(regex...)
      if @props.def.filter?
        filter = parseRegexp(@props.def.filter)
        value = value.replace(filter, '')
      errors = []
      _.each (@props.def.validators || {}), (regex, message) ->
        return if _.isFunction(regex)
        regex = parseRegexp(regex)
        if regex.test(value) != true
          errors.push message
      errors = null unless errors.length > 0
      errors

    render: ->
      def = @props.def
      defaults = {
        className    : "form-control"
        id           : "input_#{@props.name}"
        name         : @props.name
        placeholder  : def.placeholder || def.label
        defaultValue : @props.value
        onChange     : @handleChange
      }
      if def.type == 'image'
        return D.img(className: 'image-field', id: defaults.id, src: @props.value)
      validationErrors = @props.validationErrors || @validateValue(@props.value)
      C.FormFieldContainer {value: @props.value, validationErrors: validationErrors}, [
        C.FormFieldLabel(htmlFor: @props.name, label: def.label, validationErrors: validationErrors) if def.label?
        if def.type =='textarea'
          D.textarea(defaults)
        else
          D.input(_.merge defaults, type: def.type)
      ]...

  SlidingMenu: createFactory
    show: ->
      $(@refs.menu.getDOMNode()).addClass('visible')
      $(@refs.menuContainer.getDOMNode()).css(left: 0)
    hide: ->
      $(@refs.menu.getDOMNode()).removeClass('visible')
    ignore: (e) ->
      e.preventDefault()
      e.stopPropagation()
    handleTouchMove: (e) ->
      deltaX = @startX - e.changedTouches[0].screenX
      deltaX = 0 if deltaX < 0
      deltaY = @startY - e.changedTouches[0].screenY
      if !@dirLock? and (deltaX != 0 or deltaY != 0)
        if Math.abs(deltaX) > Math.abs(deltaY)
          @dirLock = 'X'
        else
          @dirLock = 'Y'
      if @dirLock == 'X'
        $(@refs.menuContainer.getDOMNode()).css(left: -deltaX)
      else if @dirLock == 'Y'
        $menuBody = $(@refs.menuBody.getDOMNode())
        $menuContainer = $(@refs.menuContainer.getDOMNode())
        @scrollTop = @lastScrollTop + deltaY
        maxScrollTop = $menuBody.outerHeight() - $menuContainer.innerHeight()
        @scrollTop = Math.max(@scrollTop, 0)
        @scrollTop = Math.min(@scrollTop, maxScrollTop)
        $menuBody.css(top: -@scrollTop)
    handleTouchStart: (e) ->
      @dirLock = null
      @startX = e.changedTouches[0].screenX
      @startY = e.changedTouches[0].screenY
      @lastScrollTop?= 0
    handleTouchEnd: (e) ->
      endX = e.changedTouches[0].screenX
      $(@refs.menuContainer.getDOMNode()).css(left: 0)
      if @dirLock == 'X' and @startX - endX > 100
        @hide()
      else if @dirLock == 'Y'
        @lastScrollTop = @scrollTop
    render: ->
      @startY = null
      D.div {ref: 'menu', className: 'sliding-menu', onClick: @hide},
        D.div {ref: 'menuContainer', className: 'sliding-menu-container', onClick: @ignore, onTouchMove: @handleTouchMove, onTouchStart: @handleTouchStart, onTouchEnd: @handleTouchEnd},
          D.div {ref: 'menuBody', className: 'sliding-menu-body'},
            D.ul {},
              _.map(@props.children || [], (item) ->
                D.li {}, item
              )...

  ModalDialog: createFactory
    show: (animate, trackHistory = true)->
      return if @visible
      @trackHistory = trackHistory
      $(@refs.dialog.getDOMNode()).addClass('animate') if animate
      $(@refs.dialog.getDOMNode()).addClass('visible')
      @visible = true
      if history?.pushState? and @trackHistory
        window.addEventListener 'popstate', @back
        history.pushState({}, null)
    back: ->
      @hide(false)
    hide: (popHistory = true)->
      @visible = false
      $(@refs.dialog.getDOMNode()).removeClass('visible')
      history.back() if history?.back? and popHistory and @trackHistory
      if history?.pushState?
        window.removeEventListener 'popstate', @back
      setTimeout (=> $(@refs.dialog.getDOMNode()).removeClass('animate') if @refs.dialog?), 500
    ignore: (e) ->
      e.preventDefault()
      e.stopPropagation()
    componentWillUnmount: ->
      @hide()
    render: ->
      D.div {ref: 'dialog', className: "modal-dialog #{@props.className || ""}"},
        D.div {className: 'modal-dialog-container'},
          D.div {className: 'modal-dialog-body'}, @props.children

  ProgressBar: createFactory
    getInitialState: -> {value: 0}
    show: (message, startingValue) ->
      @setState {message: message, value: startingValue || 0}
      @refs.dialog.show(false, false)
    setMessage: (message) -> @setState(message: message)
    setProgress: (value) -> @setState(value: value)
    hide: -> @refs.dialog.hide()
    render: ->
      value = Math.min(100, @state.value)
      D.ModalDialog {ref: 'dialog', className: 'progress-bar'},
        D.div {className: 'progress-container'},
          D.div {className: 'message'}, @state.message if @state.message?
          D.div {className: 'value', style: {right: "#{100-value}%"}}

  FocusSection: createFactory
    focus: (element) ->
      @element = $(element)
      @container.addClass("visible")
      setTimeout (=> @container.addClass("do-animate")), 0
      @handleWindowResize()
    unfocus: ->
      @container.removeClass("visible")
      @container.removeClass("do-animate")
      @element = null
    handleWindowResize: ->
      return unless @element?
      width = $(window).width()
      @container.css {
        left: -@container.parent().offset().left
        width: width
      }
      @container.find('.left').css {width: @element.offset().left - @container.offset().left - 2}
      @container.find('.right').css {width: width - (@element.offset().left - @container.offset().left + @element.outerWidth()) - 2}
      @container.find('.top').css {
        left: @element.offset().left - @container.offset().left - 2
        width: @element.outerWidth() + 4
        height: @element.offset().top - @container.offset().top - 2
      }
      @container.find('.bottom').css {
        left: @element.offset().left - @container.offset().left - 2
        width: @element.outerWidth() + 4
        height: @container.height() - (@element.offset().top - @container.offset().top + @element.outerHeight()) - 2
      }
    componentDidMount: ->
      @container = $(@refs.container.getDOMNode())
      $(window).on 'resize', @handleWindowResize
    componentWillUnmount: ->
      $(window).off 'resize', @handleWindowResize
    render: ->
      D.div {ref: 'container', className: "focus-section#{if @props.animate then ' animate' else ''} #{@props.className}"},
        D.div {className: 'inner-focus-section'},
          D.div {className: 'top'}
          D.div {className: 'right'}
          D.div {className: 'left'}
          D.div {className: 'bottom'}
}