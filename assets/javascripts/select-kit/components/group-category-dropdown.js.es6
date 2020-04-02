import ComboBoxComponent from "select-kit/components/combo-box";
import DiscourseURL from "discourse/lib/url";
import discourseComputed from "discourse-common/utils/decorators";
import { computed } from "@ember/object";
import { ajax } from "discourse/lib/ajax";


export default ComboBoxComponent.extend({
  classNames: "group-category-dropdown",
  tagName: "li",
  caretDownIcon: "caret-right",
  caretUpIcon: "caret-down",
  allowAutoSelectFirst: false,
  valueAttribute: 'name',
  value: 'test',
  content: computed(function() {
    return this.currentUser.get("current_user_icij_projects")
  }),

  @discourseComputed("content")
  filterable(content) {
    return content && content.length >= 10;
  },

  computeHeaderContent() {
    let content = this._super();

    if (!this.get("hasSelection")) {
      content.label = `<span>${I18n.t("groups.index.all")}</span>`;
    }

    return content;
  },

  @discourseComputed
  collectionHeader() {
    if (this.siteSettings.enable_group_directory ||
        (this.currentUser && this.currentUser.get('staff'))) {

      return `
        <a href="${Discourse.getURL("/groups")}" class="group-dropdown-filter">
          ${I18n.t("groups.index.all").toLowerCase()}
        </a>
      `.htmlSafe();
    }
  },

  actions: {
    onSelect(groupName) {
      DiscourseURL.routeTo(Discourse.getURL(`/groups/${groupName}/categories`));
    }
  }
});
