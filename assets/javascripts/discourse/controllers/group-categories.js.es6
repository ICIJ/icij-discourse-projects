import DiscourseURL from 'discourse/lib/url';

export default Ember.Controller.extend({
  discoveryTopics: Ember.inject.controller('discovery/topics'),
  navigationCategory: Ember.inject.controller('navigation/category'),
  application: Ember.inject.controller()

  

});
