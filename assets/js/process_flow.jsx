import React, { useMemo, useEffect, useCallback } from 'react';
import {
  ReactFlow,
  Background,
  useNodesState,
  useEdgesState,
  useReactFlow,
  ReactFlowProvider,
  Handle,
  Position,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';

// Status colors - clean PRD style
const STATUS = {
  pending: { bg: '#f8fafc', border: '#e2e8f0', dot: '#94a3b8', text: '#64748b' },
  active: { bg: '#fffbeb', border: '#fcd34d', dot: '#f59e0b', text: '#92400e' },
  completed: { bg: '#f0fdf4', border: '#86efac', dot: '#22c55e', text: '#166534' },
};

// Clean step node - PRD style
function StepNode({ data }) {
  const colors = STATUS[data.status] || STATUS.pending;
  
  return (
    <div style={{
      background: colors.bg,
      border: `2px solid ${colors.border}`,
      borderRadius: '8px',
      padding: '12px 20px',
      minWidth: '120px',
      display: 'flex',
      alignItems: 'center',
      gap: '10px',
      boxShadow: '0 1px 3px rgba(0,0,0,0.1)',
      fontFamily: 'system-ui, -apple-system, sans-serif',
    }}>
      <Handle type="target" position={Position.Top} style={{ opacity: 0 }} />
      <div style={{
        width: '8px',
        height: '8px',
        borderRadius: '50%',
        background: colors.dot,
        flexShrink: 0,
      }} />
      <div style={{
        fontSize: '13px',
        fontWeight: 500,
        color: colors.text,
        whiteSpace: 'nowrap',
      }}>
        {data.label}
      </div>
      <Handle type="source" position={Position.Bottom} style={{ opacity: 0 }} />
    </div>
  );
}

// Compact task node for parallel work
function TaskNode({ data }) {
  const colors = STATUS[data.status] || STATUS.pending;
  
  return (
    <div style={{
      background: colors.bg,
      border: `1.5px solid ${colors.border}`,
      borderRadius: '6px',
      padding: '6px 12px',
      display: 'flex',
      alignItems: 'center',
      gap: '6px',
      fontFamily: 'system-ui, -apple-system, sans-serif',
    }}>
      <Handle type="target" position={Position.Left} style={{ opacity: 0 }} />
      <div style={{
        width: '6px',
        height: '6px',
        borderRadius: '50%',
        background: colors.dot,
      }} />
      <span style={{
        fontSize: '11px',
        fontWeight: 500,
        color: colors.text,
      }}>
        {data.label}
      </span>
      <Handle type="source" position={Position.Right} style={{ opacity: 0 }} />
    </div>
  );
}

// Process Manager node - the coordinator
function ManagerNode({ data }) {
  return (
    <div style={{
      background: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
      border: '2px solid #a78bfa',
      borderRadius: '50%',
      width: '70px',
      height: '70px',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      boxShadow: '0 4px 12px rgba(139, 92, 246, 0.3)',
      fontFamily: 'system-ui, -apple-system, sans-serif',
    }}>
      <Handle type="source" position={Position.Right} style={{ opacity: 0 }} />
      <div style={{ fontSize: '16px' }}>🎯</div>
      <div style={{
        fontSize: '8px',
        fontWeight: 600,
        color: '#fff',
        textAlign: 'center',
        lineHeight: 1.1,
        marginTop: '2px',
      }}>
        Process<br/>Manager
      </div>
    </div>
  );
}

const nodeTypes = {
  step: StepNode,
  task: TaskNode,
  manager: ManagerNode,
};

// Build the flow layout - compact, single screen
function buildFlow(processState) {
  const {
    currentStep = null,
    dataSources = ['profile', 'documents', 'preferences'],
    hasSharedAssets = false,
    completedTasks = [],
  } = processState || {};

  const nodes = [];
  const edges = [];
  
  // Step status helper
  const stepOrder = ['init', 'gathering', 'transferring', 'packaging', 'uploading', 'notifying', 'purging', 'completed'];
  const getStatus = (step) => {
    const currentIdx = stepOrder.indexOf(currentStep);
    const stepIdx = stepOrder.indexOf(step);
    if (currentStep === step) return 'active';
    if (stepIdx < currentIdx || currentStep === 'completed') return 'completed';
    return 'pending';
  };

  const getTaskStatus = (taskKey) => {
    if (completedTasks.includes(taskKey)) return 'completed';
    const step = taskKey.startsWith('gather:') ? 'gathering' : 'purging';
    if (currentStep === step) return 'active';
    if (getStatus(step) === 'completed') return 'completed';
    return 'pending';
  };

  // Layout: compact vertical flow with manager on left
  const startX = 180;
  const startY = 20;
  const stepGap = 60;
  const taskGap = 30;
  
  let y = startY;

  // Process Manager - positioned on the left
  nodes.push({
    id: 'pm',
    type: 'manager',
    position: { x: 40, y: 180 },
    data: {},
  });

  // Step 1: Initialize
  nodes.push({
    id: 'init',
    type: 'step',
    position: { x: startX, y },
    data: { label: 'Initialize', status: getStatus('init') },
  });
  y += stepGap;

  // Step 2: Gather Data (with parallel tasks)
  const gatherY = y;
  nodes.push({
    id: 'gather',
    type: 'step',
    position: { x: startX, y: gatherY },
    data: { label: 'Gather Data', status: getStatus('gathering') },
  });
  edges.push({ id: 'init-gather', source: 'init', target: 'gather', type: 'smoothstep' });

  // Gather tasks - spread to the right
  const taskX = startX + 160;
  const taskStartY = gatherY - ((dataSources.length - 1) * taskGap) / 2;
  dataSources.forEach((source, i) => {
    const id = `gather-${source}`;
    nodes.push({
      id,
      type: 'task',
      position: { x: taskX, y: taskStartY + i * taskGap },
      data: { 
        label: source.charAt(0).toUpperCase() + source.slice(1).replace('_', ' '),
        status: getTaskStatus(`gather:${source}`),
      },
    });
    edges.push({ id: `e-${id}`, source: 'gather', target: id, type: 'smoothstep', style: { strokeDasharray: '4 2' } });
  });
  y += stepGap;

  // Step 3: Transfer (conditional)
  let prevId = 'gather';
  if (hasSharedAssets) {
    nodes.push({
      id: 'transfer',
      type: 'step',
      position: { x: startX, y },
      data: { label: 'Transfer Assets', status: getStatus('transferring') },
    });
    edges.push({ id: 'gather-transfer', source: 'gather', target: 'transfer', type: 'smoothstep' });
    prevId = 'transfer';
    y += stepGap;
  }

  // Step 4: Package
  nodes.push({
    id: 'package',
    type: 'step',
    position: { x: startX, y },
    data: { label: 'Package', status: getStatus('packaging') },
  });
  edges.push({ id: `${prevId}-package`, source: prevId, target: 'package', type: 'smoothstep' });
  y += stepGap;

  // Step 5: Upload
  nodes.push({
    id: 'upload',
    type: 'step',
    position: { x: startX, y },
    data: { label: 'Upload to S3', status: getStatus('uploading') },
  });
  edges.push({ id: 'package-upload', source: 'package', target: 'upload', type: 'smoothstep' });
  y += stepGap;

  // Step 6: Notify
  nodes.push({
    id: 'notify',
    type: 'step',
    position: { x: startX, y },
    data: { label: 'Notify User', status: getStatus('notifying') },
  });
  edges.push({ id: 'upload-notify', source: 'upload', target: 'notify', type: 'smoothstep' });
  y += stepGap;

  // Step 7: Purge (with parallel tasks)
  const purgeY = y;
  nodes.push({
    id: 'purge',
    type: 'step',
    position: { x: startX, y: purgeY },
    data: { label: 'Purge Data', status: getStatus('purging') },
  });
  edges.push({ id: 'notify-purge', source: 'notify', target: 'purge', type: 'smoothstep' });

  // Purge tasks
  const purgeTaskStartY = purgeY - ((dataSources.length - 1) * taskGap) / 2;
  dataSources.forEach((source, i) => {
    const id = `purge-${source}`;
    nodes.push({
      id,
      type: 'task',
      position: { x: taskX, y: purgeTaskStartY + i * taskGap },
      data: { 
        label: source.charAt(0).toUpperCase() + source.slice(1).replace('_', ' '),
        status: getTaskStatus(`purge:${source}`),
      },
    });
    edges.push({ id: `e-${id}`, source: 'purge', target: id, type: 'smoothstep', style: { strokeDasharray: '4 2' } });
  });
  y += stepGap;

  // Step 8: Complete
  nodes.push({
    id: 'done',
    type: 'step',
    position: { x: startX, y },
    data: { label: 'Complete', status: getStatus('completed') },
  });
  edges.push({ id: 'purge-done', source: 'purge', target: 'done', type: 'smoothstep' });

  // Edge from PM to active step (command flow)
  const activeStep = ['init', 'gather', 'transfer', 'package', 'upload', 'notify', 'purge', 'done']
    .find(s => {
      const stepId = s === 'gather' ? 'gathering' : s === 'purge' ? 'purging' : s;
      return getStatus(stepId) === 'active';
    });
  
  if (activeStep) {
    edges.push({
      id: 'pm-active',
      source: 'pm',
      target: activeStep,
      type: 'smoothstep',
      animated: true,
      style: { stroke: '#8b5cf6', strokeWidth: 2 },
    });
  }

  return { nodes, edges };
}

// Inner component with hooks
function FlowInner({ processState }) {
  const { fitView } = useReactFlow();
  const { nodes: initNodes, edges: initEdges } = useMemo(() => buildFlow(processState), []);
  const [nodes, setNodes, onNodesChange] = useNodesState(initNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initEdges);

  useEffect(() => {
    const { nodes: newNodes, edges: newEdges } = buildFlow(processState);
    setNodes(newNodes);
    setEdges(newEdges);
    setTimeout(() => fitView({ padding: 0.15, duration: 200 }), 50);
  }, [JSON.stringify(processState), setNodes, setEdges, fitView]);

  return (
    <ReactFlow
      nodes={nodes}
      edges={edges}
      onNodesChange={onNodesChange}
      onEdgesChange={onEdgesChange}
      nodeTypes={nodeTypes}
      fitView
      fitViewOptions={{ padding: 0.15 }}
      defaultEdgeOptions={{ type: 'smoothstep', style: { stroke: '#cbd5e1', strokeWidth: 1.5 } }}
      proOptions={{ hideAttribution: true }}
      nodesDraggable={false}
      nodesConnectable={false}
      elementsSelectable={false}
      panOnDrag={false}
      zoomOnScroll={false}
      zoomOnPinch={false}
      zoomOnDoubleClick={false}
      preventScrolling={false}
    >
      <Background color="#f1f5f9" gap={20} size={1} />
    </ReactFlow>
  );
}

// Main export - wrapped with provider
export default function ProcessFlowDiagram({ processState }) {
  return (
    <div style={{ width: '100%', height: '100%', background: '#fff', borderRadius: '8px' }}>
      <ReactFlowProvider>
        <FlowInner processState={processState} />
      </ReactFlowProvider>
    </div>
  );
}

