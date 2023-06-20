import { GlEmptyState, GlKeysetPagination } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import { SNIPPET_MAX_LIST_COUNT } from '~/profile/constants';
import SnippetsTab from '~/profile/components/snippets/snippets_tab.vue';
import SnippetRow from '~/profile/components/snippets/snippet_row.vue';
import getUserSnippets from '~/profile/components/graphql/get_user_snippets.query.graphql';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import {
  MOCK_USER,
  MOCK_SNIPPETS_EMPTY_STATE,
  MOCK_USER_SNIPPETS_RES,
  MOCK_USER_SNIPPETS_PAGINATION_RES,
  MOCK_USER_SNIPPETS_EMPTY_RES,
} from 'jest/profile/mock_data';

Vue.use(VueApollo);

describe('UserProfileSnippetsTab', () => {
  let wrapper;

  let queryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_SNIPPETS_RES);

  const createComponent = () => {
    const apolloProvider = createMockApollo([[getUserSnippets, queryHandlerMock]]);

    wrapper = shallowMountExtended(SnippetsTab, {
      apolloProvider,
      provide: {
        userId: MOCK_USER.id,
        snippetsEmptyState: MOCK_SNIPPETS_EMPTY_STATE,
      },
    });
  };

  const findSnippetRows = () => wrapper.findAllComponents(SnippetRow);
  const findGlEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findGlKeysetPagination = () => wrapper.findComponent(GlKeysetPagination);

  describe('when user has no snippets', () => {
    beforeEach(async () => {
      queryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_SNIPPETS_EMPTY_RES);
      createComponent();

      await nextTick();
    });

    it('does not render snippet row', () => {
      expect(findSnippetRows().exists()).toBe(false);
    });

    it('does render empty state with correct svg', () => {
      expect(findGlEmptyState().exists()).toBe(true);
      expect(findGlEmptyState().attributes('svgpath')).toBe(MOCK_SNIPPETS_EMPTY_STATE);
    });
  });

  describe('when snippets returns an error', () => {
    beforeEach(async () => {
      queryHandlerMock = jest.fn().mockRejectedValue({ errors: [] });
      createComponent();

      await nextTick();
    });

    it('does not render snippet row', () => {
      expect(findSnippetRows().exists()).toBe(false);
    });

    it('does render empty state with correct svg', () => {
      expect(findGlEmptyState().exists()).toBe(true);
      expect(findGlEmptyState().attributes('svgpath')).toBe(MOCK_SNIPPETS_EMPTY_STATE);
    });
  });

  describe('when snippets are returned', () => {
    beforeEach(async () => {
      queryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_SNIPPETS_RES);
      createComponent();

      await nextTick();
    });

    it('renders a snippet row for each snippet', () => {
      expect(findSnippetRows().exists()).toBe(true);
      expect(findSnippetRows().length).toBe(MOCK_USER_SNIPPETS_RES.data.user.snippets.nodes.length);
    });

    it('does not render empty state', () => {
      expect(findGlEmptyState().exists()).toBe(false);
    });

    it('adds bottom border when snippet is not last in list', () => {
      expect(findSnippetRows().at(0).classes('gl-border-b')).toBe(true);
    });

    it('does not add bottom border when snippet is last in list', () => {
      expect(
        findSnippetRows()
          .at(MOCK_USER_SNIPPETS_RES.data.user.snippets.nodes.length - 1)
          .classes('gl-border-b'),
      ).toBe(false);
    });
  });

  describe('Snippet Pagination', () => {
    describe('when user has one page of snippets', () => {
      beforeEach(async () => {
        queryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_SNIPPETS_RES);
        createComponent();

        await nextTick();
      });

      it('does not render pagination', () => {
        expect(findGlKeysetPagination().exists()).toBe(false);
      });
    });

    describe('when user has multiple pages of snippets', () => {
      beforeEach(async () => {
        queryHandlerMock = jest.fn().mockResolvedValue(MOCK_USER_SNIPPETS_PAGINATION_RES);
        createComponent();

        await nextTick();
      });

      it('does render pagination', () => {
        expect(findGlKeysetPagination().exists()).toBe(true);
      });

      it('when nextPage is clicked', async () => {
        findGlKeysetPagination().vm.$emit('next');

        await nextTick();

        expect(queryHandlerMock).toHaveBeenCalledWith({
          id: convertToGraphQLId(TYPENAME_USER, MOCK_USER.id),
          first: SNIPPET_MAX_LIST_COUNT,
          last: null,
          afterToken: MOCK_USER_SNIPPETS_RES.data.user.snippets.pageInfo.endCursor,
        });
      });

      it('when previousPage is clicked', async () => {
        findGlKeysetPagination().vm.$emit('prev');

        await nextTick();

        expect(queryHandlerMock).toHaveBeenCalledWith({
          id: convertToGraphQLId(TYPENAME_USER, MOCK_USER.id),
          first: null,
          last: SNIPPET_MAX_LIST_COUNT,
          beforeToken: MOCK_USER_SNIPPETS_RES.data.user.snippets.pageInfo.startCursor,
        });
      });
    });
  });
});
