import property from 'ember-addons/ember-computed-decorators';
import TopicList from 'discourse/models/topic-list';

export default {
  name: 'extend-topic-list-for-projects',
  initialize() {

    TopicList.reopen({

      @property()
      icijGroupNames() {
        return this.site.get('icij_group_names');
      }

    });
  }
};
