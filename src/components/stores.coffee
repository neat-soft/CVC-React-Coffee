{EventEmitter} = require('events')
_ = require('lodash')
d = require('./common')
moment = require('moment')

Store = class Store extends EventEmitter
  constructor: () -> @state = {}
  setRestClient: (restClient) -> @restClient = restClient
  preload: (state) -> @state = state
  getState: -> _.cloneDeep(@state)

PagingStore = class PagingStore extends Store
  reset: ->
    @state.items = []
    @state.totalCount = 0
    @state.loading = false
    @state.page = 0
    @state.scrollTop = 0

  init: () ->
    return if @state?.items?.length > 0
    @reset()
    @loadNextPage()

  preload: (items, totalCount) ->
    return if @state.items?.length > 0
    @state.items = items if items?
    @state.totalCount = totalCount if totalCount?
    @state.page = 1

  loadNextPage: ->
    return if @state.loading
    @state.loading = true
    @doLoadNextPage @state.page+1, {
      success: (results) =>
        if results.items.length == 0
          @state.totalCount = @state.items.length
        else
          @state.page+=1
          @state.items = (@state.items || []).concat(results.items)
          @state.totalCount = results.totalFound
        @state.loading = false
        @emit 'change'
      error: (err...) =>
        @state.loading = false
        @emit 'change'
    }

  isLoading: -> @state.loading

  getItem: (index) ->
    return @state.items[index] unless index>=@state.items.length
    @loadNextPage() if index <= @state.totalCount and @state.items.length < @state.totalCount
    null

  getScrollTop: -> @state.scrollTop
  setScrollTop: (scrollTop) -> @state.scrollTop = scrollTop
  getLoadedCount: ->
    return 0 unless @state.items?.length?
    loaded = @state.items?.length
    loaded++ if @state.totalCount > loaded
    loaded

exports.BrowseStore = class BrowseStore extends PagingStore
  init: (defaultFilter) ->
    return if @state.defaultFilter?
    @state.defaultFilter = defaultFilter
    @state.filter?=defaultFilter
    super()

  doLoadNextPage: (page, cb) ->
    @restClient.post "", {filter: @state.filter, pageSize: 10, page: page}, cb

  search: ->
    @reset()
    @loadNextPage()
    @emit 'change'
    undefined

  handleFilterChange: (filterName, newValue) ->
    updates = {}
    updates[filterName] = newValue
    _.merge @state.filter, d.formToObj(updates)
    @search()

  getProfile: (index) -> @getItem(index)
  getFilter: -> _.cloneDeep(@state.filter)

exports.PhotosStore = class PhotoStore extends Store
  init: (photos) ->
    @state.photos = photos unless @state.photos

  makePrimary: (guid) ->
    @restClient.post '/make_primary', guid: guid, (results) =>
      @state.photos = results.photos.photos
      @emit 'change'

  delete: (guid) ->
    @restClient.delete '', guid: guid, (results) =>
      @state.photos = results.photos.photos
      @emit 'change'

  getPhotos: -> @state.photos
  refresh: ->
    @restClient.get "", {}, (results) =>
      @state.photos = results.photos.photos
      @emit 'change'

exports.InboxStore = class InboxStore extends PagingStore
  doLoadNextPage: (page, cb) ->
    @restClient.post "", {pageSize: 10, page: @state.page + 1}, cb
  delete: (conversationWithGuid) ->
    @restClient.post "/#{conversationWithGuid}/delete", null, =>
      conv = _.find @state.items, (conv) -> conv.fromProfileGuid == conversationWithGuid
      conv.deleted = true if conv?
      @emit 'change'

exports.ConversationStore = class ConversationStore extends Store
  init: (conversation) ->
    @state.conversations?={}
    return unless conversation?
    @state.conversations[conversation.conversationWithGuid] = conversation

  getConversation: (conversationWithGuid) ->
    @state.conversations[conversationWithGuid]

  sendMessage: (conversationWithGuid, text, cb) ->
    @restClient.put '', {text:text}, =>
      @state.conversations[conversationWithGuid].messages.push({text: text, type: 'sent', timestamp: moment().utc()})
      cb()
      @emit 'change'

exports.NotificationStore = class NotificationStore extends Store
  init: (counters) ->
    @state.counters = counters

  updateCounters: (counters) ->
    @state.counters = counters
    @emit 'change'

  updateDiscoverCounter: (value) ->
    @state.counters.newDiscover = value
    @emit 'change'

  getNewMessages: -> @state?.counters?.newMessages
  getNewDiscover: -> @state?.counters?.newDiscover
  getNewVisitors: -> @state?.counters?.newVisitors
  getNewLikedBy: -> @state?.counters?.newLikedBy

exports.ProfileStore = class ProfileStore extends Store
  flipLikeFlag: ->
    action = if @state.flags?.liked then '/unlike' else '/like'
    @restClient.post action, {}, (profile) =>
      @state = profile
      @emit 'change'

  hide: ->
    @restClient.post '/hide', {}, (profile) =>
      @state = profile
      @emit 'change'

  report: (reason) ->
    @restClient.post '/report', {reason: reason}, () =>

exports.DiscoverStore = class DiscoverStore extends Store
  loadNextProfile: ->
    if @state.items?.length > 0
      @state.lastProfile = @state.items.shift()
      if @state.items.length < 5
        @loadMoreProfiles()
    else
      @loadMoreProfiles()
    @emit 'change'
  loadMoreProfiles: ->
    return if @state.loading or !@restClient?
    return if @state.totalFound == 0
    skipProfiles = _.map(@state.items, (i) -> i.guid)
    skipProfiles = skipProfiles.concat(@state.pending)
    @state.loading = true
    @restClient.post '', {skipProfiles: skipProfiles},
      error: (err) =>
        @state.loading = false
        @state.error = true
        @emit 'change'
      success: (results) =>
        noProfiles = @state.items.length == 0
        @state.items = @state.items.concat(results.profiles)
        @state.totalFound = results.totalFound
        @state.totalFound = @state.items.length if results.profiles.length == 0
        @state.loading = false
        @emit 'change'
  preload: (items, totalFound) ->
    super({items: items, totalFound: totalFound})
    @state.pending = []
    @state.loading = false
    @emit 'change'
  action: (action) ->
    guid = @getCurrentProfile()?.guid
    return unless guid?
    @state.totalFound--
    @state.pending.push(guid)
    done = =>
      @state.pending = _.without @state.pending, guid
      @emit 'change'
    @restClient.post "#{action}/#{guid}", {},
      error: done
      success: done
    @loadNextProfile()
  getStatus: ->
    if @state.items.length == 0 and @state.loading == false
      'empty'
    else if (@state.items.length == 0 and @state.loading) or @state.pending.length > 3
      'loading'
    else
      'ok'
  getTotalFound: -> @state.totalFound
  getCurrentProfile: -> @state.items?[0]
  like: -> @action('/like')
  hide: -> @action('/hide')

exports.ProfileListStore = class ProfileListStore extends PagingStore
  action: (action, guid) ->
    return unless guid?
    done = => @emit 'change'
    @restClient.post "/#{action}/#{guid}", {},
      error: done
      success: done
  doLoadNextPage: (page, cb) ->
    @restClient.post "", {pageSize: 10, page: @state.page + 1}, cb
  like: (guid) ->
    profile = _.find(@state.items, (item) -> item.guid == guid)
    return unless profile?
    if profile.liked!=true
      @action('like', guid)
      profile.liked = true
      profile.hidden = false if profile?
    else
      @action('unlike', guid)
      profile.liked = false
    undefined
  hide: (guid) ->
    @action('hide', guid)
    profile = _.find(@state.items, (item) -> item.guid == guid)
    profile.hidden = true if profile?
    profile.liked = false if profile?
    undefined
  block: (guid) ->
    @action('block', guid)
    profile = _.find(@state.items, (item) -> item.guid == guid)
    profile.blocked = true if profile?
    undefined

exports.LocationStore = class LocationStore extends Store
  preload: (locations) ->
    @state.locations = locations
  updateLocations: (postalCode) ->
    return if (postalCode || "").length == 0
    @restClient.get "/locations/#{postalCode}", {}, (locations) =>
      @state.locations = locations
      @emit 'change'
  getLocations: -> @state.locations || []
  getLocation: (guid) -> _.filter(@state.locations, (l) -> l.guid == guid)[0]
