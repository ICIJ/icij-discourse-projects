import { default as computed } from "ember-addons/ember-computed-decorators";
import GroupController from 'discourse/controllers/group';

// this exact same logic isn't working in the general initializer, so i've put it into its own, which seems to solve the problem

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

        const defaultTabs = [icijGroupsTab, Tab.create({ name: "activity" })];

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

        defaultTabs.push(icijMembersTab);

        return defaultTabs;
      }
    })
  }
}
