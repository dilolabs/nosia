# Medietilsynet AI Platform - Project Roadmap

## 🎯 Project Vision

Transform Nosia into a brand-aligned, accessible AI assistant for Medietilsynet that feels like an official, trusted government tool. The platform will enable employees to leverage AI capabilities while maintaining strict security, privacy, and usability standards.

## 📊 Project Scope

### Your Focus Areas
1. **Brand-aligned UI** using Dembrandt extraction from medietilsynet.no
2. **Chatbot creation & library system** - build, organize, and deploy chatbots
3. **Model flexibility** - switch between local AI and OpenAI/other providers

### Parallel Work (Other Team)
- RAG (Retrieval-Augmented Generation) implementation
- Prompt library system

### Future Integrations (Deferred)
- SharePoint Online, OneDrive, Exchange
- Acos WebSak+ case management system
- Other enterprise systems

---

## 🗓️ Implementation Phases

### **Phase 1: Foundation - Medietilsynet Brand Integration** (Week 1)

**Goal:** Make Nosia look and feel like an official Medietilsynet product

**Epic: Brand-Aligned UI with Design System Integration**

#### User Stories

**1. Extract Design System from medietilsynet.no**
- Use Dembrandt to extract design tokens (colors, typography, spacing, borders)
- Convert to W3C Design Tokens (DTCG) format
- Document extracted design system in `/Medietilsynet/design-system/`
- **Acceptance Criteria:**
  - Design tokens successfully extracted
  - Documentation includes color palette, typography scale, spacing system
  - Tokens stored in accessible format

**2. Convert Design Tokens to Tailwind Configuration**
- Map extracted tokens to Tailwind theme
- Create custom color palette matching Medietilsynet brand
- Configure custom fonts, spacing, and component styles
- **Acceptance Criteria:**
  - Tailwind config reflects Medietilsynet design system
  - All colors, fonts, spacing aligned with brand
  - Design system is reusable across all components

**3. Build Theme System with Accessibility**
- Implement light mode (primary)
- Implement dark mode
- Implement high-contrast mode (WCAG AAA compliance)
- Create theme switcher component
- **Acceptance Criteria:**
  - Three theme variants working correctly
  - Themes persist across sessions
  - All themes meet WCAG accessibility standards
  - Theme switcher accessible via keyboard and screen readers

**4. Apply Branding to Nosia UI**
- Update main layout with Medietilsynet styling
- Replace logos, colors, and typography
- Redesign components: header, navigation, chat interface, buttons, forms, cards
- Ensure government-standard professional appearance
- **Acceptance Criteria:**
  - All UI components use Medietilsynet design system
  - Interface feels cohesive and professional
  - Branding consistent across all pages
  - No generic/default styling remains

**5. Norwegian Localization**
- Translate UI strings to Norwegian Bokmål
- Set up i18n infrastructure for future language support
- Ensure date/time formats follow Norwegian standards
- **Acceptance Criteria:**
  - All user-facing text in Norwegian
  - Fallback to English where needed
  - i18n system extensible for additional languages

**Deliverables:**
- ✅ Branded Nosia interface
- ✅ Theme system (light/dark/high-contrast)
- ✅ Design system documentation
- ✅ Norwegian localization
- ✅ Accessibility compliance report

---

### **Phase 2: Chatbot Builder & Library** (Weeks 2-3)

**Goal:** Enable users to create, organize, and deploy chatbots with custom knowledge bases

**Epic: Chatbot Creation & Management System**

#### User Stories

**1. Chatbot Creation Interface**
- Build form to create new chatbot
- Configure chatbot properties:
  - Name and description
  - System instructions/role
  - Tone and style settings
  - Model selection
- Test chatbot before publishing
- **Acceptance Criteria:**
  - Intuitive creation form
  - Real-time chatbot testing
  - Validation for required fields
  - Save as draft functionality

**2. Chatbot Knowledge Base Management**
- Upload documents to chatbot (PDF, text, Word, etc.)
- Connect to existing RAG system (integration with other team's work)
- View and manage attached documents
- Update/remove documents easily
- Show document processing status
- **Acceptance Criteria:**
  - Multiple file format support
  - Drag-and-drop upload
  - Document preview
  - Clear processing status indicators
  - Easy document removal

**3. Chatbot Library/Marketplace**
- Browse available chatbots
- Search and filter:
  - By category (HR, Legal, IT, etc.)
  - By department
  - By creator
  - By access level (internal/external)
- Preview chatbot capabilities before use
- Display chatbot usage statistics
- **Acceptance Criteria:**
  - Clean, organized library view
  - Fast search and filtering
  - Preview shows chatbot description and capabilities
  - Usage metrics visible to admins

**4. Chatbot Access Controls**
- Set chatbot visibility:
  - Internal (specific employees)
  - Organization-wide
  - External/public
- Assign to user groups
- Optional admin approval workflow
- **Acceptance Criteria:**
  - Granular permission settings
  - User groups management
  - Approval queue for admins
  - Access violations blocked

**5. Chatbot Deployment Options**
- Generate embed code for external deployment
- Create shareable internal links
- Track usage analytics per chatbot
- Monitor chatbot performance
- **Acceptance Criteria:**
  - Copy-paste embed code generation
  - Shareable links with access controls
  - Analytics dashboard (users, messages, satisfaction)
  - Performance metrics tracking

**Deliverables:**
- ✅ Chatbot builder interface
- ✅ Knowledge base management
- ✅ Chatbot library/marketplace
- ✅ Access control system
- ✅ Deployment options
- ✅ Analytics dashboard

---

### **Phase 3: Model Provider Flexibility** (Week 4)

**Goal:** Support multiple AI providers (local models, OpenAI, Azure OpenAI, etc.)

**Epic: Multi-Provider AI Integration**

#### User Stories

**1. Model Configuration UI (Admin)**
- Admin panel to configure AI providers
- Support for multiple providers:
  - Local models (current)
  - OpenAI
  - Azure OpenAI
  - Anthropic Claude
  - Google Gemini
- Securely store API keys
- Set default provider
- **Acceptance Criteria:**
  - Admin can add/remove providers
  - API key storage encrypted
  - Test connection functionality
  - Clear error messages for misconfiguration

**2. User Model Selection**
- Let users choose which model to use (if admin allows)
- Display model capabilities:
  - Supports vision
  - Supports reasoning
  - Supports function calling
  - Context window size
- Remember user preference per chat
- **Acceptance Criteria:**
  - Model selector in chat interface
  - Clear capability indicators
  - Preference persists across sessions
  - Only show admin-approved models

**3. Model-Specific Feature Handling**
- Enable/disable features based on model capabilities
  - Image generation (DALL-E, Stable Diffusion)
  - Vision (GPT-4V, Claude)
  - Reasoning mode (o1, o3)
- Handle different API formats gracefully
- Provide fallback options when feature unavailable
- **Acceptance Criteria:**
  - Features auto-enable/disable per model
  - Seamless switching between providers
  - No breaking changes when switching models
  - Clear user messaging about limitations

**4. Cost & Usage Tracking**
- Track token usage per provider
- Display cost estimates (for paid APIs)
- Set usage limits per user/department
- Generate cost reports for admins
- **Acceptance Criteria:**
  - Accurate token counting
  - Real-time usage display
  - Configurable limits
  - Cost reports exportable

**Deliverables:**
- ✅ Multi-provider support
- ✅ Admin configuration panel
- ✅ User model selection
- ✅ Model-specific feature handling
- ✅ Usage & cost tracking

---

## 📋 Feature Mapping to Roadmap

### From features.md → Implementation

**✅ Covered in Current Roadmap:**

| Feature Category | Status | Phase |
|-----------------|--------|-------|
| User Experience (1.1) | ✅ Planned | Phase 1 |
| Chatbots (7.1, 7.2, 7.3) | ✅ Planned | Phase 2 |
| Admin Controls (4.2, 6.1) - partial | ✅ Planned | Phase 2, 3 |
| Core AI (4.3) - Chat with LLM | ✅ Exists | - |
| Core AI (4.3) - RAG | ✅ In Progress | Other Team |
| Prompt Management (3.1, 3.2) | ✅ In Progress | Other Team |

**⏳ Future Phases (Deferred):**

| Feature Category | Status | Notes |
|-----------------|--------|-------|
| Document & Data Integration (4.4, 5.1, 5.2) | ⏳ Future | Requires system access |
| Core AI - Export to Word/PowerPoint | ⏳ Future | Phase 4+ |
| Core AI - Image generation | ⏳ Future | Phase 4+ |
| Core AI - Reasoning mode | ⏳ Future | Phase 4+ |
| Core AI - Excel/CSV analysis | ⏳ Future | Phase 4+ |
| Analytics & Statistics (10.1) | ⏳ Future | Phase 5+ |
| Security & Privacy (8.1, 9.1, 9.2) | ⏳ Ongoing | Throughout |
| Documentation & Support (2.1, 2.2) | ⏳ Ongoing | Throughout |

---

## 🎨 Design System Guidelines

### Extracted from medietilsynet.no

**To be documented after Dembrandt extraction:**

- Primary color palette
- Secondary/accent colors
- Typography (fonts, sizes, weights)
- Spacing system
- Component styles (buttons, cards, inputs)
- Iconography
- Logo usage guidelines

### Accessibility Requirements

- **WCAG 2.1 Level AA minimum** (AAA where possible)
- Color contrast ratios: 4.5:1 for text, 3:1 for large text
- Keyboard navigation support
- Screen reader compatibility
- High-contrast mode support
- Focus indicators visible

---

## 🛠️ Technical Stack

### Frontend
- **Framework:** Ruby on Rails (existing)
- **Styling:** Tailwind CSS (utility-first, no simple CSS)
- **Theme System:** CSS custom properties + JavaScript
- **i18n:** Rails I18n

### Backend
- **Framework:** Ruby on Rails
- **Database:** PostgreSQL with pgvector
- **AI Integration:** Multiple providers via unified interface
- **Background Jobs:** SolidQueue

### Development Tools
- **Design Extraction:** Dembrandt
- **Version Control:** Git with feature branch workflow
- **Testing:** Pytest (backend), Vitest/Jest (frontend)
- **Documentation:** Markdown

---

## 📦 Git Workflow

Following project rules for branching:

1. **Feature branches from main:**
   - `feature/medietilsynet-branding`
   - `feature/chatbot-builder`
   - `feature/model-provider-flexibility`

2. **Commit after each user story completion**

3. **Push to remote regularly**

4. **Pull Request required before merge to main**

5. **No direct commits to main**

---

## 🎯 Success Criteria

### Phase 1 Success (Branding)
- [ ] Nosia interface uses Medietilsynet design system
- [ ] Three theme variants working (light/dark/high-contrast)
- [ ] All text in Norwegian
- [ ] WCAG AA accessibility compliance
- [ ] Looks professional and government-appropriate
- [ ] Design system documented for team

### Phase 2 Success (Chatbots)
- [ ] Users can create and configure chatbots
- [ ] Chatbot library is organized and searchable
- [ ] Knowledge base integration works seamlessly
- [ ] Access controls function correctly
- [ ] Deployment options available and tested

### Phase 3 Success (Model Flexibility)
- [ ] Multiple AI providers supported
- [ ] Users can switch between models
- [ ] Features adapt to model capabilities
- [ ] Usage tracking operational
- [ ] No breaking changes during provider switches

---

## 📞 Team Coordination

### Your Responsibilities
- Brand & UI implementation
- Chatbot system
- Model provider integration
- Documentation

### Other Team's Responsibilities
- RAG implementation
- Prompt library system
- Backend AI optimization

### Collaboration Points
- RAG integration with chatbot knowledge base
- Shared component library
- API contracts between systems

---

## 📅 Timeline Estimate

**Phase 1:** 1 week (branding foundation)  
**Phase 2:** 2 weeks (chatbot system)  
**Phase 3:** 1 week (model flexibility)  

**Total:** ~4 weeks for core deliverables

---

## 🚀 Getting Started

1. ✅ Repository forked and set up
2. ✅ Docker environment running
3. ✅ Features documented
4. ✅ Roadmap created
5. ⏭️ Next: Extract design system with Dembrandt
6. ⏭️ Then: Apply branding to Nosia

---

**Last Updated:** 2025-12-16  
**Status:** Planning Complete, Ready for Implementation
