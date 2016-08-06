React = require('react');
LandingPage = require('../components/app')

props = JSON.parse(document.getElementById('initial-state').innerHTML)

React.render(
  LandingPage(props),
  document.getElementById('app')
)
