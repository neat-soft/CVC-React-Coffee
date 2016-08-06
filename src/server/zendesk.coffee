exports.ZendeskApi = ($p, $options) ->
  zendesk = require('node-zendesk')
  client = zendesk.createClient($options)
  convertError =
    error: (err) ->
      if err.result?
        try
          errData = JSON.parse(err.result.toString())
          message = errData?.error?.message || errData?.error?.title || errData.details || errData
        catch e
      $p.error(message || err)

  return self = {
    createTicket: (userName, ipAddress, userAgent, accountIdentifier, emailAddress, message) ->
      ticket = {
        ticket:
          subject: message
          description: message
          requester:
            name: userName
            email: emailAddress
            locale_id: 8
          custom_fields:
            userName: userName
            32087307: ipAddress
            32060098: userAgent
            32060298: accountIdentifier
      }
      $p.wrap(client.tickets.create ticket, $p.ecb()).then(convertError).then ->
  }