import property from 'ember-addons/ember-computed-decorators';
import Site from 'discourse/models/site';

export default {
  name: 'extend-site-for-projects',
  initialize() {

    Site.reopen({

      @property()
      projectsList() {
        this.get("available_icij_groups");
      }

    });
  }
};
