import showModal from "discourse/lib/show-modal";
import OpenComposer from "discourse/mixins/open-composer";
import CategoryList from "discourse/models/category-list";
import { defaultHomepage } from 'discourse/lib/utilities';
import TopicList from "discourse/models/topic-list";
import { ajax } from "discourse/lib/ajax";
import PreloadStore from "preload-store";
import { searchPriorities } from "discourse/components/concerns/category-search-priorities";
import { get } from "@ember/object";
import DiscourseRoute from "discourse/routes/discourse";

export function buildGroupPage(type) {
  return DiscourseRoute.extend(OpenComposer, {
    type,

    titleToken() {
      return I18n.t(`groups.${type}`);
    },

    model() {
      return this.modelFor("group").findLists({ type });
    },

    setupController(controller, model) {
      this.controllerFor("group").setProperties({
        displayButtons: true
      }),
      this.controllerFor("group-categories").setProperties({
        model,
        type
      });
    },

    renderTemplate() {
      this.render("group-categories");
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
          custom_fields: {},
          search_priority: searchPriorities.normal
        });

        showModal("edit-category", { model });
        this.controllerFor("edit-category").set("selectedTab", "general");
      }
    }
  })
}

export default buildGroupPage("categories");
