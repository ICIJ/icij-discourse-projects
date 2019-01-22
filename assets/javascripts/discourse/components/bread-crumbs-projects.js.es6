import DiscourseURL from "discourse/lib/url";
import { default as computed } from "ember-addons/ember-computed-decorators";
import Group from "discourse/models/group";
const { isEmpty } = Ember;

//  A breadcrumb including category drop downs
export default Ember.Component.extend({
  classNameBindings: ["hidden:hidden", ":category-breadcrumb"],
  tagName: "ol",
  parentCategory: Em.computed.alias("category.parentCategory"),

});
