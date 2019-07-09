import { default as computed } from "ember-addons/ember-computed-decorators";
import GroupController from 'discourse/controllers/group';

const Tab = Ember.Object.extend({
  init() {
    this._super();
    let name = this.get("name");
    this.set("route", this.get("route") || `group.` + name);
    this.set("message", I18n.t(`groups.${this.get("i18nKey") || name}`));
  }
});

export default {
  name: 'extend-group-controller-for-projects',
  before: 'inject-discourse-objects',
  initialize() {

    GroupController.reopen({
      @computed("showMessages", "model.user_count", "canManageGroup")
      icijTabs(showMessages, userCount, canManageGroup, icijGroups) {
        const icijMembersTab = Tab.create({
          name: "members",
          route: "group.index",
          icon: "users",
          i18nKey: "members.title"
        });

        icijMembersTab.set("count", userCount);

        const icijGroupsTab = Tab.create({
          name: "groups",
          route: "group.categories",
          i18nKey: "icij.title"
        })

        const defaultTabs = [icijMembersTab, icijGroupsTab, Tab.create({ name: "activity" })];

        if (showMessages) {
          defaultTabs.push(
            Tab.create({
              name: "messages",
              i18nKey: "messages"
            })
          );
        }

        if (canManageGroup) {
          defaultTabs.push(
            Tab.create({
              name: "manage",
              i18nKey: "manage.title",
              icon: "wrench"
            })
          );
        }

        return defaultTabs;
      }
    })
  }
}
