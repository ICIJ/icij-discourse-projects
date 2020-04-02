import property from 'ember-addons/ember-computed-decorators';
import User from 'discourse/models/user';
import Category from 'discourse/models/category';
export default {
  name: 'extend-category-for-projects',
  initialize() {

    Category.reopenClass({
      listIcijProjectCategories() {
        return User.currentProp("icij_project_categories");
      }
    });
  }
};
