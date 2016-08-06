exports.DefaultProxyHandler = (target) ->
  this.target = target
  undefined

exports.DefaultProxyHandler.prototype = {
  getOwnPropertyDescriptor: (name) ->
    desc = Object.getOwnPropertyDescriptor(this.target, name)
    desc.configurable = true if (desc?)
    return desc

  getPropertyDescriptor: (name) ->
    desc = Object.getPropertyDescriptor(this.target, name);
    desc.configurable = true if (desc?)
    return desc

  getOwnPropertyNames: -> Object.getOwnPropertyNames(this.target)
  getPropertyNames: -> Object.getPropertyNames(this.target)
  defineProperty: (name, desc) -> Object.defineProperty(this.target, name, desc)
  delete: (name) -> delete this.target[name]
  fix: ->
    if (!Object.isFrozen(this.target))
      return undefined;
    props = {};
    Object.getOwnPropertyNames(this.target).forEach(((name) ->
      props[name] = Object.getOwnPropertyDescriptor(this.target, name);
    ).bind(this));
    return props;

  has: (name) -> return name in this.target
  hasOwn: (name) -> return ({}).hasOwnProperty.call(this.target, name)
  get: (receiver, name) -> this.target[name]
  set: (receiver, name, value) ->
    this.target[name] = value
    return true

  enumerate: () -> name for name in this.target

  iterate: () ->
    props = this.enumerate();
    i = 0;
    return {
      next: () ->
        throw StopIteration if (i == props.length)
        return props[i++]
    }
  keys: () -> Object.keys(this.target)
}
