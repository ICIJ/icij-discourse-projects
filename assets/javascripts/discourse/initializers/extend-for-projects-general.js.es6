import { withPluginApi } from "discourse/lib/plugin-api";
import showModal from "discourse/lib/show-modal";
import { searchPriorities } from "discourse/components/concerns/category-search-priorities";
import EditCategoryGeneral from 'discourse/components/edit-category-general'
import PermissionType from "discourse/models/permission-type";
import { on } from "discourse-common/utils/decorators";
import BreadCrumbs from "discourse/components/bread-crumbs";
import DiscourseURL from "discourse/lib/url";
import discourseComputed from "discourse-common/utils/decorators";
import { filter } from "@ember/object/computed";
import Component from "@ember/component";
import deprecated from "discourse-common/lib/deprecated";
import { computed } from "@ember/object";
import TopicController from "discourse/controllers/topic"
import PreloadStore from "preload-store";
import CategoryList from "discourse/models/category-list";
import TopicList from "discourse/models/topic-list";
import Group from "discourse/models/group";
import { ajax } from "discourse/lib/ajax";
import EmberObject from "@ember/object";
import GroupController from "discourse/controllers/group";
import OpenComposer from "discourse/mixins/open-composer";
import Composer from "discourse/models/composer";
import GroupIndexController from "discourse/controllers/group-index";
import Category from "discourse/models/category";
import Session from "discourse/models/session";
import User from "discourse/models/user";

function initializePlugin(api) {
  api.reopenWidget("quick-access-panel", {
    getItems() {
      let data = Session.currentProp(`${this.key}-items`)
      let isArray = data instanceof Array
      if (isArray) {
        data = data.filter(i => i.icon !== "user")
      }
      return data || [];
    }
  }),

  api.modifySelectKit("group-dropdown").modifyContent((context, existingContent) => {
    let projects = User.currentProp("current_user_icij_projects");
    projects = projects.map(p => p.name);
    return existingContent.filter(g => projects.includes(g));
  }),

  api.modifySelectKit("category-chooser").modifyContent((context, existingContent) => {
    const icijProjectCategories = Category.listIcijProjectCategories();
    const container = Discourse.__container__;
    const route = container.lookup("route:application");
    const isGroupRoute = route.controller.currentRouteName.indexOf('group.') === 0
    const discoveryRouteName = route.controller.currentRouteName;

    let discoveryRoutesToCheck = ["discovery.categoryNone", "discovery.latestParentCategory", "discovery.topParentCategory", "discovery.newParentCategory", "discovery.unreadParentCategory", "discovery.parentCategory", "discovery.category"]

    if (isGroupRoute) {
      let groupName = route.controllerFor('group').get('model.name');
      let categories = existingContent.filter(c => (icijProjectCategories.includes(c.id) && (c.group_names[0] === groupName)))
      return categories
    } else if (discoveryRoutesToCheck.includes(discoveryRouteName)) {
      let groupName = route.controllerFor('discovery').get('category.group_names') || []
      let categories = existingContent.filter(c => (icijProjectCategories.includes(c.id) && (c.group_names[0] === groupName[0])))
      if (groupName.length === 0) {
        return existingContent.filter(c => icijProjectCategories.includes(c.id))
      } else {
        return categories;
      }
    } else {
      let categories = existingContent.filter(c => icijProjectCategories.includes(c.id))
      return categories
    }
  }),

  api.modifySelectKit("category-drop").modifyContent((context, existingContent) => {
    const container = Discourse.__container__;
    const route = container.lookup("route:application");
    const discoveryRouteName = route.controller.currentRouteName;

    let groupName = route.controllerFor('discovery').get('category.group_names') || []

    let discoveryRoutesToCheck = ["discovery.categoryNone", "discovery.latestParentCategory", "discovery.topParentCategory", "discovery.newParentCategory", "discovery.unreadParentCategory", "discovery.parentCategory", "discovery.category"]

    if (discoveryRoutesToCheck.includes(discoveryRouteName)) {
      return existingContent.filter(c => {
        if (c.id !== "all-categories") {
          return (c.group_names[0] === groupName[0])
        }
      });
    } else {
      return existingContent;
    }
  }),

  api.modifyClass("component:group-dropdown", {
    actions: {
      onChange(groupName) {
        if ((this.groups || []).includes(groupName)) {
          DiscourseURL.routeToUrl(`/g/${groupName}/categories`);
        } else {
          DiscourseURL.routeToUrl(`/g`);
        }
      }
    }
  }),

  api.modifyClass("model:category", {
    save() {
      const id = this.id;
      const url = id ? `/categories/${id}` : "/categories";

      return ajax(url, {
        data: {
          name: this.name,
          slug: this.slug,
          color: this.color,
          text_color: this.text_color,
          secure: this.secure,
          permissions: this._permissionsForUpdate(),
          auto_close_hours: this.auto_close_hours,
          auto_close_based_on_last_post: this.get(
            "auto_close_based_on_last_post"
          ),
          position: this.position,
          email_in: this.email_in,
          email_in_allow_strangers: this.email_in_allow_strangers,
          group_names: this.get("group_names"),
          subcategory_group_names: this.get("subcategory_group_names"),
          group_permissions: this.get("group_permissions"),
          mailinglist_mirror: this.mailinglist_mirror,
          parent_category_id: this.parent_category_id,
          uploaded_logo_id: this.get("uploaded_logo.id"),
          uploaded_background_id: this.get("uploaded_background.id"),
          allow_badges: this.allow_badges,
          custom_fields: this.custom_fields,
          topic_template: this.topic_template,
          all_topics_wiki: this.all_topics_wiki,
          allowed_tags: this.allowed_tags,
          allowed_tag_groups: this.allowed_tag_groups,
          allow_global_tags: this.allow_global_tags,
          required_tag_group_name: this.required_tag_groups
            ? this.required_tag_groups[0]
            : null,
          min_tags_from_required_group: this.min_tags_from_required_group,
          sort_order: this.sort_order,
          sort_ascending: this.sort_ascending,
          topic_featured_link_allowed: this.topic_featured_link_allowed,
          show_subcategory_list: this.show_subcategory_list,
          num_featured_topics: this.num_featured_topics,
          default_view: this.default_view,
          subcategory_list_style: this.subcategory_list_style,
          default_top_period: this.default_top_period,
          minimum_required_tags: this.minimum_required_tags,
          navigate_to_first_post_after_read: this.get(
            "navigate_to_first_post_after_read"
          ),
          search_priority: this.search_priority,
          reviewable_by_group_name: this.reviewable_by_group_name
        },
        type: id ? "PUT" : "POST"
      });
    }
  }),

  api.modifyClass("controller:group", {
    showing: "categories",

    tabs(
      showMessages,
      userCount,
      requestCount,
      canManageGroup,
      allowMembershipRequests,
      icijGroupsTab
    ) {
      defaultTabs.push(
        Tab.create({
          name: "groups",
          route: "group.categories",
          i18nKey: "icij.title"
        })
      )

      return defaultTabs;
    }
  }),

  api.modifyClass("route:group", {
    setupController(controller, model) {
      controller.setProperties({
        model,
        displayButtons: false
      });
    }
  }),

  api.modifyClass("route:group-messages", {
    setupController(controller, model) {
      this.controllerFor("group").setProperties({
        displayButtons: false
      })
    }
  }),

  api.modifyClass("route:group-members", {
    beforeModel() {
      this.controllerFor("group").setProperties({
        displayButtons: false
      })
    }
  }),

  api.modifyClass("route:group-activity-posts", {
    setupController(controller, model) {
      this.controllerFor("group").setProperties({
        displayButtons: false
      })
    }
  }),

  api.modifyClass("route:discovery", {
    actions: {
      createCategory() {
        const groups = this.site.available_icij_projects
        const filterCategory = this.topicTrackingState.filterCategory || [];

        let setPermissions = null;
        if (filterCategory.length === 0) {
          setPermissions = [];
        } else {
          setPermissions = filterCategory.group_permissions
        }

        const model = this.store.createRecord("category", {
          color: "0088CC",
          text_color: "FFFFFF",
          group_permissions: setPermissions,
          available_groups: groups.map(g => g.name),
          allow_badges: true,
          topic_featured_link_allowed: true,
          custom_fields: {},
          search_priority: searchPriorities.normal
        });

        showModal("edit-category", { model });
        this.controllerFor("edit-category").set("selectedTab", "general");
      }
    }
  }),

  api.modifyClass("route:discovery-categories", {
    actions: {
      createCategory() {
        const groups = this.site.available_icij_projects

        const model = this.store.createRecord("category", {
          color: "0088CC",
          text_color: "FFFFFF",
          group_permissions: [],
          available_groups: groups.map(g => g.name),
          allow_badges: true,
          topic_featured_link_allowed: true,
          custom_fields: {},
          search_priority: searchPriorities.normal
        });

        showModal("edit-category", { model });
        this.controllerFor("edit-category").set("selectedTab", "general");
      }
    }
  })

  api.modifyClass("component:edit-category-general", {
    actions: {
      onSelectGroup(selectedGroup) {
        this.setProperties({
          interactedWithDropdowns: true,
          selectedGroup
        });
      },

      onSelectPermission(selectedPermission) {
        this.setProperties({
          interactedWithDropdowns: true,
          selectedPermission
        });
      },

      editPermissions() {
        if (!this.get("category.is_special")) {
          this.set("editingPermissions", true);
        }
      },

      addPermission(group, id) {
        if (!this.get("category.is_special")) {
          this.category.addPermission({
            group_name: group + "",
            permission: PermissionType.create({ id: parseInt(id, 10) })
          });
        }

        this.setProperties({
          selectedGroup: this.get("category.availableGroups.firstObject"),
          showPendingGroupChangesAlert: false,
          interactedWithDropdowns: false
        });
      },

      removePermission(permission) {
        if (!this.get("category.is_special")) {
          this.category.removePermission(permission);
        }
      }
    }
  })
};

export default {
  name: "extend-for-projects-general",

  initialize() {
    EditCategoryGeneral.reopen({
      editingPermissions: false,
      selectedGroup: null,
      selectedPermission: null,
      showPendingGroupChangesAlert: false,
      interactedWithDropdowns: false,

      @on("init")
      _setup() {
        this.setProperties({
          selectedGroup: this.get("category.availableGroups.firstObject"),
          selectedPermission: this.get(
            "category.availablePermissions.firstObject.id"
          )
        });
      }
    });

    TopicController.reopen({
      showBottom: false,
    }),

    GroupController.reopen({
      displayButtons: false,
      displayMessageDeleteButtons: true
    }),

    GroupIndexController.reopen({
      displayButtons: false,
      displayMessageDeleteButtons: true
    }),

    BreadCrumbs.reopen({
      currentProjectName: computed(function() {
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

        if (names.length > 0) {
          return names;
        } else {
          return "all projects";
        }
      }),

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
    }),

    Group.reopen({
      findLists(opts) {
        opts = opts || {};
        const type = opts.type || "categories";
        const data = {};

        return ajax(`/g/${this.name}/${type}.json`).then(result => {
          return EmberObject.create({
            categories: CategoryList.categoriesFrom(this.store, result.lists),
            topics: TopicList.topicsFrom(this.store, result.lists),
            can_create_category: result.lists.category_list.can_create_category,
            can_create_topic: result.lists.category_list.can_create_topic,
            draft_key: result.lists.category_list.draft_key,
            draft: result.lists.category_list.draft,
            draft_sequence: result.lists.category_list.draft_sequence
          })
        })
      }
    }),

    withPluginApi("0.8.37", api => initializePlugin(api));
  }
};
