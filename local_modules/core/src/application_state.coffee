exports.ApplicationState = ($options, dynamoDb) ->
  tableDef =
    tableName: "#{$options.tablePrefix}-application-state"
    throughput: {readCapacityUnits: 2, writeCapacityUnits: 2}
    attributeDefinitions: [
      {attributeName: 'key', attributeType: "S"}
      {attributeName: 'value', attributeType: "S"}
      {attributeName: 'updateVector', attributeType: "S"}
    ]
    keyDefinition: {key: {type: "S", keyType: "HASH"}}

  dynamoDb.existingTable(tableDef).then (stateTable) ->
    return self = {
      _stateTable: stateTable
      get: (key) ->
        stateTable.getItem({key: key}, {consistentRead: true}).then (v) -> v?.value

      set: (key, value) ->
        stateTable.putItem(key: key, value: value)

      remove: (key) ->
        stateTable.deleteItem(key: key)
    }