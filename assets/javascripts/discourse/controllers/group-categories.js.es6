import DiscourseURL from 'discourse/lib/url';
import { default as computed } from "ember-addons/ember-computed-decorators";

export default Ember.Controller.extend({
  discoveryTopics: Ember.inject.controller('discovery/topics'),
  navigationCategory: Ember.inject.controller('navigation/category'),
  application: Ember.inject.controller()
});
