import showModal from "discourse/lib/show-modal";
import OpenComposer from "discourse/mixins/open-composer";
import CategoryList from "discourse/models/category-list";
import { defaultHomepage } from 'discourse/lib/utilities';
import TopicList from "discourse/models/topic-list";
import { ajax } from "discourse/lib/ajax";
import PreloadStore from "preload-store";

const GroupCategoriesRoute = Discourse.Route.extend(OpenComposer, {
  renderTemplate: function() {
    this.render('group-categories', {into: 'application'});
  },

  findCategories() {
    let style = !this.site.mobileView &&
      this.siteSettings.desktop_category_page_style;

    let parentCategory = this.get("model.parentCategory");
    if (parentCategory) {
      return CategoryList.listForParent(this.store, parentCategory);
    } else if (style === "categories_and_latest_topics") {
      return this._findCategoriesAndTopics('latest');
    } else if (style === "categories_and_top_topics") {
      return this._findCategoriesAndTopics('top');
    }

    return CategoryList.list(this.store);
  },

  model() {
    return this.findCategories().then(model => {
      const tracking = this.topicTrackingState;
      if (tracking) {
        tracking.sync(model, "categories");
        tracking.trackIncoming("categories");
      }
      return model;
    });
  },

  _findCategoriesAndTopics(filter) {
      return ajax(`/groups/${this.modelFor('group').get('name')}/categories.json`).then(result => {
        return Ember.Object.create({
          group: result.group,
          categories: CategoryList.categoriesFrom(this.store, result.extras),
          topics: TopicList.topicsFrom(this.store, result.extras),
          icij_group_names: TopicList.icijGroupNamess,
          can_create_category: result.extras.category_list.can_create_category,
          can_create_topic: result.extras.category_list.can_create_topic,
          draft_key: result.extras.category_list.draft_key,
          draft: result.extras.category_list.draft,
          draft_sequence: result.extras.category_list.draft_sequence
        });
      });
  },

  setupController(controller, model) {
    controller.set("model", model);

    this.controllerFor("group-categories").setProperties({
      canCreateTopic: model.get("can_create_topic"),
    });
  },

  actions: {
    createTopic() {
      const model = this.controllerFor("group-categories").get('model');
      if (model.draft) {
        this.openTopicDraft(model);
      } else {
        this.openComposer(this.controllerFor("group-categories"));
      }
    },

    createCategory() {
      const groups = this.site.available_icij_projects

      const model = this.store.createRecord("category", {
        color: "0088CC",
        text_color: "FFFFFF",
        group_permissions: [{ group_name: this.modelFor('group').get('name'), permission_type: 1 }],
        available_groups: groups.map(g => g.name),
        allow_badges: true,
        topic_featured_link_allowed: true,
        custom_fields: {}
      });

      showModal("edit-category", { model });
      this.controllerFor("edit-category").set("selectedTab", "general");
    }
  }
});

export default GroupCategoriesRoute;
