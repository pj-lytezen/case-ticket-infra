# INSTRUCTIONS
Define a detailed strategy that uses `Generative AI` to automate customer support inquiries and tickets.
The proposed workflow consist of a `chatbot conversation` pattern with redirect to live customer service representative if unable to answer within a specific generative (LLM) response threshold.

# GENERAL REQUIREMENTS
Requirements include, but are not limited to:
1. Conversation session management 
	- user conversation sessions need to be uniquely identifiable to facilitate context summaries metrics.  
	- Entire questions need to be stored and retrieved in a manner that best facilitates the use of RAG systems.
2. Human Escalation
	- Do not guess, hallucinate or hypothesize responses. If relevant data is not found or unavailable or response accuracy is below a specific threshold then redirect conversation to live customer service representative.
	- When escalating to human, provide conversation (chatbot) history along with a context summary.
	- continue conversation chain until issue is resolved. 
3. Post Resolution
	- Summarize conversation along with resolution. Include any document reference links, urls, paths, etc. The summary should highlight and buld context around the initial question that started the conversation.
	- each question and response, whether human provided or AI generated, should be identifiable and stored for later `RAG` retrieval and metrics.
	- each questioned should be categorized via one or two word tags for easy reference.
4. Metrics
	- Length of time to resolve issue
	- Number of similar questions.
	- Propose any other metrics that might be relevant.
5. Retrieval Augmented Generation (RAG) Preferences
	- Hybrid RAG - Search of document store along with vector store.