import showModal from "discourse/lib/show-modal";
import OpenComposer from "discourse/mixins/open-composer";
import { scrollTop } from "discourse/mixins/scroll-top";
import { defaultHomepage } from 'discourse/lib/utilities';
import TopicList from "discourse/models/topic-list";
import { ajax } from "discourse/lib/ajax";
import PreloadStore from "preload-store";

import { queryParams } from "discourse/controllers/discovery-sortable";

const GroupTopicsRoute = Discourse.Route.extend(OpenComposer, {
  renderTemplate: function() {
    this.render('group-topics', {into: 'application'});
  },

  findTopics() {
    return this.store.findFiltered("topicList", {
      filter: `topics/groups/${this.modelFor("group").get("name")}`
    });
  },

  model() {
    return this.findTopics().then(model => {
      const tracking = this.topicTrackingState;
      if (tracking) {
        tracking.sync(model, "topics");
        tracking.trackIncoming("topics");
      }
      return model;
    });
  },

  setupController(controller, model) {
    controller.set("model", model);

    this.controllerFor("group-topics").setProperties({
      canCreateTopic: model.get("can_create_topic"),
    });
  },

  actions: {
    createTopic() {
      const model = this.controllerFor("group-topics").get('model');
      if (model.draft) {
        this.openTopicDraft(model);
      } else {
        this.openComposer(this.controllerFor("group-categories"));
      }
    },

    createCategory() {
      const groups = this.site.icij_projects_for_security

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

export default GroupTopicsRoute;
