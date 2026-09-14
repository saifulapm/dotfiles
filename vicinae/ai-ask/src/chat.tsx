import { type LaunchProps } from "@vicinae/api";
import { ChatView } from "./lib/chat-view";

export default function Command(
  props: LaunchProps<{ arguments: Arguments.Chat }>,
) {
  // Same three ways in as the one-shot command. Opened bare — the ordinary
  // case for a chat — there is no question yet and the view shows the
  // conversations it saved earlier.
  const question = (props.arguments?.question || props.fallbackText || "").trim();
  return <ChatView initialQuestion={question || undefined} />;
}
