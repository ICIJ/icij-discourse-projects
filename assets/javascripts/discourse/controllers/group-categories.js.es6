import DiscourseURL from 'discourse/lib/url';
import { default as computed } from "ember-addons/ember-computed-decorators";

const Tab = Ember.Object.extend({
  init() {
    this._super();
    let name = this.get("name");
    this.set("route", this.get("route") || `group.` + name);
    this.set("message", I18n.t(`groups.${this.get("i18nKey") || name}`));
  }
});

export default Ember.Controller.extend({
  discoveryTopics: Ember.inject.controller('discovery/topics'),
  navigationCategory: Ember.inject.controller('navigation/category'),
  application: Ember.inject.controller(),
  counts: null,
  showing: "members",
  destroying: null,

  @computed("showMessages", "model.group.user_count", "canManageGroup")
  icijTabs(showMessages, userCount, canManageGroup, icijGroups) {
    const icijMembersTab = Tab.create({
      route: "group.index",
      icon: "users.members",
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
  },

  @computed("model.group.is_group_user")
  showMessages(isGroupUser) {
    if (!this.siteSettings.enable_personal_messages) {
      return false;
    }

    return isGroupUser || (this.currentUser && this.currentUser.admin);
  },

  @computed("model.group.is_group_owner", "model.group.automatic")
  canEditGroup(isGroupOwner, automatic) {
    return !automatic && isGroupOwner;
  },

  @computed(
    "model.name",
    "model.flair_url",
    "model.flair_bg_color",
    "model.flair_color"
  )
  avatarFlairAttributes(groupName, flairURL, flairBgColor, flairColor) {
    return {
      primary_group_flair_url: flairURL,
      primary_group_flair_bg_color: flairBgColor,
      primary_group_flair_color: flairColor,
      primary_group_name: groupName
    };
  },

  @computed("model.group.messageable")
  displayGroupMessageButton(messageable) {
    return this.currentUser && messageable;
  },

  @computed("model", "model.automatic")
  canManageGroup(model, automatic) {
    return (
      this.currentUser &&
      (this.currentUser.canManageGroup(model) ||
        (this.currentUser.admin && automatic))
    );
  },

  actions: {
    messageGroup() {
      this.send("createNewMessageViaParams", this.get("model.group.name"));
    },

    destroy() {
      const group = this.get("model.group");
      this.set("destroying", true);

      bootbox.confirm(
        I18n.t("admin.groups.delete_confirm"),
        I18n.t("no_value"),
        I18n.t("yes_value"),
        confirmed => {
          if (confirmed) {
            group
              .destroy()
              .then(() => {
                this.transitionToRoute("groups.index");
              })
              .catch(error => {
                Ember.Logger.error(error);
                bootbox.alert(I18n.t("admin.groups.delete_failed"));
              })
              .finally(() => this.set("destroying", false));
          } else {
            this.set("destroying", false);
          }
        }
      );
    }
  }
});
