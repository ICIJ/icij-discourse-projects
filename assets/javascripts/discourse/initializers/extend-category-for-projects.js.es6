import property from 'ember-addons/ember-computed-decorators';
import Category from 'discourse/models/category';

export default {
  name: 'extend-category-for-projects',
  initialize() {

    Category.reopenClass({

      listIcijProjectCategories() {
        return Discourse.Site.currentProp("icijCategoriesList");
      }

    });
  }
};
