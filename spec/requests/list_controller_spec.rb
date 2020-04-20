# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ListController do
  describe '#group_topics' do
    describe 'when an invalid group name is given' do
      it 'should return the right response' do
        group = Fabricate(:icij_group)

        user = Fabricate(:user)
        group.add(user)

        user2 = Fabricate(:user)
        group.add(user2)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(group.id => 1)
        private_cat.save

        group.update!(categories: [private_cat])

        topic =  Fabricate(:topic, category: private_cat, user: user)
        topic2 = Fabricate(:topic, user: user2)
        another_topic = Fabricate(:topic)

        get "/topics/groups/something.json"

        expect(response.status).to eq(404)
      end
    end

    describe 'for an anon user' do
      describe 'public visible group' do
        it 'should return the right response' do
          group = Fabricate(:icij_group)

          user = Fabricate(:user)
          group.add(user)

          user2 = Fabricate(:user)
          group.add(user2)

          private_cat = Fabricate(:category)
          private_cat.set_permissions(group.id => 1)
          private_cat.save

          group.update!(categories: [private_cat])

          topic =  Fabricate(:topic, category: private_cat, user: user)
          topic2 = Fabricate(:topic, user: user2)
          another_topic = Fabricate(:topic)

          get "/topics/groups/#{group.name}.json"

          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)["topic_list"]).to be_present
        end
      end

      describe 'restricted group' do
        it 'should return the right response' do
          group = Fabricate(:icij_group)

          user = Fabricate(:user)
          group.add(user)

          user2 = Fabricate(:user)
          group.add(user2)

          private_cat = Fabricate(:category)
          private_cat.set_permissions(group.id => 1)
          private_cat.save

          group.update!(categories: [private_cat])

          group.update!(visibility_level: Group.visibility_levels[:members])

          topic =  Fabricate(:topic, category: private_cat, user: user)
          topic2 = Fabricate(:topic, user: user2)
          another_topic = Fabricate(:topic)

          get "/topics/groups/#{group.name}.json"

          expect(response.status).to eq(403)
        end
      end
    end

    describe 'for a normal user' do
      before { sign_in(Fabricate(:user)) }

      describe 'restricted group' do
        it 'should return the right response' do
          group = Fabricate(:icij_group)
          group.update!(visibility_level: Group.visibility_levels[:members])

          get "/topics/groups/#{group.name}.json"

          expect(response.status).to eq(403)
        end
      end
    end

    describe 'for a group user' do
      it 'should be able to view the topics started by icij project group users' do
        user = Fabricate(:user)
        sign_in(user)

        group = Fabricate(:icij_group)
        group.add(user)
        group.update!(visibility_level: Group.visibility_levels[:members])

        user2 = Fabricate(:user)
        group.add(user2)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(group.id => 1)
        private_cat.save

        group.update!(categories: [private_cat])

        topic =  Fabricate(:topic, category: private_cat, user: user2)
        topic2 =  Fabricate(:topic, category: private_cat, user: user)

        get "/topics/groups/#{group.name}.json"

        expect(response.status).to eq(200)

        topics = JSON.parse(response.body)["topic_list"]["topics"]

        expect(topics.map { |topic| topic["id"] }).to include(
          topic.id, topic2.id
        )
      end

      it "should not return topics started by non-icij project group users" do
        user = Fabricate(:user)
        sign_in(user)

        group = Fabricate(:icij_group)
        group.add(user)
        group.update!(visibility_level: Group.visibility_levels[:members])

        user2 = Fabricate(:user)
        another_group = Fabricate(:icij_group)
        another_group.add(user2)
        another_group.update!(visibility_level: Group.visibility_levels[:members])

        private_cat = Fabricate(:category)
        private_cat.set_permissions(group.id => 1)
        private_cat.save

        another_private_cat = Fabricate(:category)
        another_private_cat.set_permissions(another_group.id => 1)
        another_private_cat.save

        group.update!(categories: [private_cat])
        another_group.update!(categories: [another_private_cat])

        topic =  Fabricate(:topic, category: another_private_cat, user: user2)
        topic2 =  Fabricate(:topic, category: private_cat, user: user)

        get "/topics/groups/#{group.name}.json"

        expect(response.status).to eq(200)

        topics = JSON.parse(response.body)["topic_list"]["topics"]

        expect(topics.map { |topic| topic["id"] }).to include(
          topic2.id
        )

        expect(topics.map { |topic| topic["id"] }).to_not include(
          topic.id
        )

        get "/topics/groups/#{another_group.name}.json"

        expect(response.status).to eq(403)
      end
    end
  end
end
