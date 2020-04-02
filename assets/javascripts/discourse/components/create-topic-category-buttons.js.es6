import discourseComputed from "discourse-common/utils/decorators";
import { on, observes } from "discourse-common/utils/decorators";
import Component from "@ember/component";

export default Ember.Component.extend({
  tagName: '',

   @discourseComputed('hasDraft')
  createTopicLabel(hasDraft)
  {
    return hasDraft ? 'topic.open_draft': 'topic.create';
  },

   @discourseComputed()
  createCategoryLabel() {
    return "category.create";
  }
});
