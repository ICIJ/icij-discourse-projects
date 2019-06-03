import property from 'ember-addons/ember-computed-decorators';
import Composer from 'discourse/models/composer';

export default {
  name: 'extend-category-for-projects',
  before: 'inject-discourse-objects',
  initialize() {
    Composer.reopen({
      @property("privateMessage", "archetype.hasOptions")
      showUnfilteredCategoryChooser(isPrivateMessage, hasOptions) {
        const manyCategories = this.site.get('categories').length > 1;
        let pathNames = document.location.pathname.split('/');
        const onProjectPage = ((pathNames.length === 4) && (pathNames[3] === "categories"));

        return !isPrivateMessage && (hasOptions || manyCategories) && !onProjectPage;
      },

      @property("privateMessage", "archetype.hasOptions")
      showProjectCategoryChooser(isPrivateMessage, hasOptions) {
        const manyCategories = this.site.get('categories').length > 1;
        let pathNames = document.location.pathname.split('/');
        const onProjectPage = ((pathNames.length === 4) && (pathNames[3] === "categories"));

        return !isPrivateMessage && (hasOptions || manyCategories) && onProjectPage;
      }
    });
  }
};
