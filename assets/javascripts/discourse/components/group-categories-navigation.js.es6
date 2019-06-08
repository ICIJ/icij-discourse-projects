import computed from "ember-addons/ember-computed-decorators";

export default Ember.Component.extend({
  tagName: '',

  @computed()
  icijGroupNames() {
    return this.site.get('icij_group_names') || this.site.get('icij_project_names') || [];
  }
});
