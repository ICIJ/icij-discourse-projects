import property from 'ember-addons/ember-computed-decorators';
import DNavigation from 'discourse/components/d-navigation';

export default {
  name: 'extend-d-navigation-for-projects',
  initialize() {

    DNavigation.reopen({

      @property()
      projects() {
        return this.site.get("available_icij_projects");
      },

      @property()
      createCategoryLabel() {
        return "category.create";
      }

    });
  }
};
