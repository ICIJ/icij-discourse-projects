require 'rails_helper'

RSpec.describe ListController do
  let(:group) { Fabricate(:icij_group) }
  describe '#group_topics' do
    %i{user user2}.each do |user|
      let(user) do
        user = Fabricate(:user)
        group.add(user)
        user
      end
    end


    private_cat = Fabricate(:category)
    private_cat.set_permissions(group.id => 1)
    private_cat.save

    group.update!(categories: [private_cat])


    let!(:topic) { Fabricate(:topic, category: private_cat, user: user) }
    let!(:topic2) { Fabricate(:topic, user: user2) }
    let!(:another_topic) { Fabricate(:topic) }

    describe 'when an invalid group name is given' do
      it 'should return the right response' do
        get "/topics/groups/something.json"

        expect(response.status).to eq(404)
      end
    end

    describe 'for an anon user' do
      describe 'public visible group' do
        it 'should return the right response' do
          get "/topics/groups/#{group.name}.json"

          byebug
          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)["topic_list"]).to be_present
        end
      end

      describe 'restricted group' do
        before { group.update!(visibility_level: Group.visibility_levels[:staff]) }

        it 'should return the right response' do
          get "/topics/groups/#{group.name}.json"

          expect(response.status).to eq(403)
        end
      end
    end

    describe 'for a normal user' do
      before { sign_in(Fabricate(:user)) }

      describe 'restricted group' do
        before { group.update!(visibility_level: Group.visibility_levels[:staff]) }

        it 'should return the right response' do
          get "/topics/groups/#{group.name}.json"

          expect(response.status).to eq(403)
        end
      end
    end

    describe 'for a group user' do
      before do
        sign_in(user)
      end

      it 'should be able to view the topics started by group users' do
        get "/topics/groups/#{group.name}.json"

        expect(response.status).to eq(200)

        topics = JSON.parse(response.body)["topic_list"]["topics"]

        expect(topics.map { |topic| topic["id"] }).to contain_exactly(
          topic.id, topic2.id
        )
      end
    end
  end
end
