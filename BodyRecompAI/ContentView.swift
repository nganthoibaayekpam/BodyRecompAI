import SwiftUI
import GoogleGenerativeAI
import FirebaseFirestore

// 1. Structure to define a single chat bubble
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

// 2. Main App View with Bottom Navigation Tabs
struct ContentView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}

// 3. The iMessage-Style Chat Interface
struct ChatView: View {
    let model = GenerativeModel(name: "gemini-3-flash-preview", apiKey: Secrets.geminiKey)
    
    @State private var userInput = ""
    @State private var isThinking = false
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Hello! Let's get to work on your body recomposition. How can I help?", isUser: false)
    ]
    
    // NEW: Hidden variable to store the user's stats
    @State private var userProfileContext = "User profile not yet loaded."

    var body: some View {
        VStack {
            // Chat Display Area
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                        
                        if isThinking {
                            HStack {
                                ProgressView("Coach is typing...")
                                    .padding()
                                Spacer()
                            }
                            .id("thinking")
                        }
                    }
                    .padding()
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            HStack(alignment: .bottom) {
                TextField("Ask about macros, workouts...", text: $userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(userInput.isEmpty || isThinking ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(userInput.isEmpty || isThinking)
            }
            .padding()
        }
        // NEW: Fetch data the moment this screen appears
        .onAppear {
            fetchUserProfile()
        }
    }
    
    func sendMessage() {
        let messageToSend = userInput
        messages.append(ChatMessage(text: messageToSend, isUser: true))
        userInput = ""
        isThinking = true
        
        Task {
            do {
                // NEW: Inject the userProfileContext silently into the prompt
                let prompt = "You are an expert fitness coach specializing in body recomposition. \(userProfileContext) Answer this user query: \(messageToSend)"
                let response = try await model.generateContent(prompt)
                
                if let text = response.text {
                    messages.append(ChatMessage(text: text, isUser: false))
                }
            } catch {
                messages.append(ChatMessage(text: "Error generating response. \(error.localizedDescription)", isUser: false))
            }
            isThinking = false
        }
    }
    
    // NEW: Function to pull data from Firebase
    func fetchUserProfile() {
        // Ensure we point to the correct "bodyrecomp" database
        let db = Firestore.firestore(database: "bodyrecomp")
        
        db.collection("users").document("test_user_01").getDocument { document, error in
            if let document = document, document.exists {
                // Extract the numbers, default to 0 if they don't exist
                let weight = document.get("currentWeight") as? Double ?? 0.0
                let height = document.get("height") as? Double ?? 0.0
                let bodyFat = document.get("bodyFatPercentage") as? Double ?? 0.0
                
                // Format the hidden instruction for the AI
                userProfileContext = "The user you are talking to has the following stats: Weight: \(weight)kg, Height: \(height)cm, Body Fat: \(bodyFat)%. Tailor all your advice, calorie goals, and workout intensities specifically to these metrics."
                print("Profile successfully loaded into AI context.")
            } else {
                print("Profile document does not exist.")
            }
        }
    }
}

// 4. Custom View for Blue and Gray Bubbles
// 4. Custom View for Blue and Gray Bubbles
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            // Adds at least 50 points of space on the left for user messages
            if message.isUser { Spacer(minLength: 50) }
            
            Text(LocalizedStringKey(message.text))
                .padding(12)
                .background(message.isUser ? Color.blue : Color(UIColor.systemGray5))
                .foregroundColor(message.isUser ? .white : .black)
                .cornerRadius(16)
            
            // Adds at least 50 points of space on the right for AI messages
            if !message.isUser { Spacer(minLength: 50) }
        }
    }
}

// 5. The Profile Screen with Firebase Save
struct ProfileView: View {
    @State private var weight = ""
    @State private var height = ""
    @State private var bodyFat = ""
    @State private var saveStatus = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Current Stats")) {
                    TextField("Weight (kg)", text: $weight)
                        .keyboardType(.decimalPad)
                    TextField("Height (cm)", text: $height)
                        .keyboardType(.decimalPad)
                    TextField("Body Fat (%)", text: $bodyFat)
                        .keyboardType(.decimalPad)
                }
                
                Button(action: saveUserStats) {
                    Text("Save to Cloud")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                
                if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .foregroundColor(saveStatus.contains("Error") ? .red : .green)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Profile")
        }
    }
    
    func saveUserStats() {
        let db = Firestore.firestore(database: "default")
        
        // Convert the typed text into numbers
        let weightVal = Double(weight) ?? 0.0
        let heightVal = Double(height) ?? 0.0
        let bodyFatVal = Double(bodyFat) ?? 0.0
        
        db.collection("users").document("test_user_01").setData([
            "currentWeight": weightVal,
            "height": heightVal,
            "bodyFatPercentage": bodyFatVal,
            "goal": "Recomposition",
            "lastUpdated": Timestamp()
        ]) { error in
            if let error = error {
                saveStatus = "Error: \(error.localizedDescription)"
            } else {
                saveStatus = "Success! Data saved to Firebase."
                
                // Clear the form fields after successful save
                weight = ""
                height = ""
                bodyFat = ""
            }
        }
    }
}
