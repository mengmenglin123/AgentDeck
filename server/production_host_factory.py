"""Assemble project-aware production Host components from typed config."""

from __future__ import annotations

from dataclasses import dataclass

from agent_session_runtime import AgentSessionRuntime
from agent_drivers import build_agent_driver
from bridge_agent_loop import AgentBridgeLoop
from bridge_websocket import BridgeWebSocketServer, BridgeWebSocketTransport, WebSocketConfig
from production_adapter import AgentSpec, ProductionAgentAdapter
from production_host_config import ProductionHostConfig
from production_management import ProductionManagementServer
from session_activity import SessionActivity
from session_journal import SessionJournal
from project_router import ProjectAgentRouter, ProjectTerminalRouter
from pty_terminal_adapter import PtySpec, PtyTerminalAdapter
from session_store import ProjectSessionStore
from terminal_bridge_loop import TerminalBridgeLoop
from workspace_allowlist import WorkspaceAllowlist


@dataclass
class ProductionHostComponents:
    config: ProductionHostConfig
    workspace: WorkspaceAllowlist
    session_store: ProjectSessionStore
    agent_router: ProjectAgentRouter
    terminal_router: ProjectTerminalRouter | None
    transport: BridgeWebSocketTransport
    server: BridgeWebSocketServer
    management: ProductionManagementServer

    def close(self) -> None:
        self.server.shutdown()
        self.management.shutdown()
        self.agent_router.close()
        if self.terminal_router is not None:
            self.terminal_router.close()


def build_production_host(config: ProductionHostConfig) -> ProductionHostComponents:
    workspace = WorkspaceAllowlist(config.workspace_roots)
    permission_gate = config.security.build_permission_gate()
    session_store = ProjectSessionStore(
        config.session_store_path,
        projects=tuple(project.name for project in config.projects),
        max_bytes=config.session_store_max_bytes,
    )
    agent_loops: dict[str, AgentBridgeLoop] = {}
    terminal_loops: dict[str, TerminalBridgeLoop] = {}
    for project in config.projects:
        workdir_resolver = workspace.message_resolver(default=project.workdir)
        agent_adapter = ProductionAgentAdapter(
            AgentSpec(
                agent_type=project.agent_type,
                command=project.command,
                capabilities=project.capabilities,
                close_stdin_after_send=project.close_stdin_after_send,
            ),
            max_sessions=project.max_sessions,
            workdir_validator=workspace.resolve,
        )
        agent_loops[project.name] = AgentBridgeLoop(
            AgentSessionRuntime(
                agent_adapter,
                driver_factory=lambda session_key, reply_ctx, driver=project.driver: build_agent_driver(
                    driver,
                    session_key,
                    reply_ctx,
                ),
                permission_gate=permission_gate,
            ),
            workdir_resolver=workdir_resolver,
        )
        if project.terminal_command is not None:
            terminal_adapter = PtyTerminalAdapter(
                PtySpec(command=project.terminal_command),
                max_sessions=project.max_sessions,
                workdir_validator=workspace.resolve,
            )
            terminal_loops[project.name] = TerminalBridgeLoop(
                terminal_adapter,
                workdir_resolver=workdir_resolver,
                permission_gate=permission_gate,
                require_open_permission=config.security.terminal_open_required,
            )

    agent_router = ProjectAgentRouter(
        agent_loops,
        default_project=config.default_project,
        session_registry=session_store,
    )
    terminal_router = (
        ProjectTerminalRouter(terminal_loops, default_project=config.default_project)
        if terminal_loops and config.default_project in terminal_loops
        else ProjectTerminalRouter(terminal_loops, default_project=None)
        if terminal_loops
        else None
    )
    activity = SessionActivity()
    transport = BridgeWebSocketTransport(
        agent_router,
        WebSocketConfig(
            token=config.bridge_token,
            max_frame_bytes=config.max_frame_bytes,
            poll_interval=config.poll_interval,
        ),
        terminal_loop=terminal_router,
        journal=SessionJournal(observer=activity.observe),
    )
    server = BridgeWebSocketServer(
        transport,
        host=config.bridge_host,
        port=config.bridge_port,
        backlog=config.backlog,
    )
    management = ProductionManagementServer(
        config.projects,
        default_project=config.default_project,
        token=config.mgmt_token,
        sessions=session_store,
        close_session=lambda session_key: _close_host_session(
            session_key,
            agent_router=agent_router,
            terminal_router=terminal_router,
        ),
        active_sessions=lambda: tuple(dict.fromkeys((
            *agent_router.active_sessions,
            *(terminal_router.active_sessions if terminal_router is not None else ()),
        ))),
        pending_permissions=permission_gate.pending_for if permission_gate is not None else None,
        session_activity=activity.get,
        bridge_port=config.bridge_port,
        host=config.mgmt_host,
        port=config.mgmt_port,
    )
    return ProductionHostComponents(
        config=config,
        workspace=workspace,
        session_store=session_store,
        agent_router=agent_router,
        terminal_router=terminal_router,
        transport=transport,
        server=server,
        management=management,
    )


def _close_host_session(
    session_key: str,
    *,
    agent_router: ProjectAgentRouter,
    terminal_router: ProjectTerminalRouter | None,
) -> None:
    agent_router.close_session(session_key)
    if terminal_router is not None:
        terminal_router.close_session(session_key)
