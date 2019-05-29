import DiscourseURL from "discourse/lib/url";
import { default as computed } from "ember-addons/ember-computed-decorators";
import Group from "discourse/models/group";
const { isEmpty } = Ember;

//  A breadcrumb including category drop downs
export default Ember.Component.extend({
  classNameBindings: ["hidden:hidden", ":category-breadcrumb"],
  tagName: "ol",
  parentCategory: Em.computed.alias("category.parentCategory"),

  @computed()
  currentProjectName() {
    let names;
    switch (true) {
      case this.isGroupRoute():
        names = [ this.route().controllerFor('group').get('model.name') ]
      case this.isTopicRoute():
        names = this.route().controllerFor('topic').get('model.category.group_names') || []
        break;
      case this.isDiscoveryRoute():
        names = this.route().controllerFor('discovery').get('category.group_names') || []
    }
    return _.chain(names)
      .compact()
      .unique()
      .filter(n => this.site.icij_project_names.indexOf(n) > -1)
      .first()
  },

  route () {
    return Discourse.__container__.lookup("route:application");
  },

  isGroupRoute () {
    return this.route().controller.currentRouteName.indexOf('group.') === 0
  },

  isDiscoveryRoute () {
    return this.route().controller.currentRouteName.indexOf('discovery.') === 0
  },

  isTopicRoute () {
    return this.route().controller.currentRouteName.indexOf('topic.') === 0
  }
});
